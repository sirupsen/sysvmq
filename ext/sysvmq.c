#include <ruby.h>
#include <ruby/util.h>
#include <ruby/thread.h>
#include <ruby/io.h>

#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/msg.h>

#include <stdlib.h>
#include <errno.h>
#include <stdio.h>

typedef struct {
  long mtype;
  char mtext[];
} 
sysvmq_msgbuf_t;


struct timeval polling_interval;

typedef struct {
  key_t             key;
  int               id;
  size_t            buffer_size;
  sysvmq_msgbuf_t*  msgbuf;
}
sysvmq_t;

static void
sysvmq_mark(void *ptr)
{
  // noop, no Ruby objects in the internal struct currently
}

static void
sysvmq_free(void *ptr)
{
  sysvmq_t* sysv = ptr;
  xfree(sysv->msgbuf);
  xfree(sysv);
}

static size_t
sysvmq_memsize(const void* ptr)
{
  const sysvmq_t* sysv = ptr;
  return sizeof(sysvmq_t) + sizeof(char) * sysv->buffer_size;
}

static const rb_data_type_t
sysvmq_type = {
  "sysvmq_type",
  {
    sysvmq_mark,
    sysvmq_free,
    sysvmq_memsize
  }
};

static VALUE
sysvmq_alloc(VALUE klass)
{
  sysvmq_t* sysv;
  VALUE obj = TypedData_Make_Struct(klass, sysvmq_t, &sysvmq_type, sysv);

  sysv->key         = 0;
  sysv->id          = -1;
  sysv->buffer_size = 0;
  sysv->msgbuf      = NULL;

  return obj;
}

// int msgctl(int msqid, int cmd, struct msqid_ds *buf);
// http://man7.org/linux/man-pages/man2/msgctl.2.html
//
// Controls the queue with IPC_SET, IPC_INFO and IPC_RMID
static VALUE
sysvmq_stats(int argc, VALUE *argv, VALUE self)
{
  struct msqid_ds info;
  VALUE info_hash;
  VALUE cmd;
  sysvmq_t* sysv;

  // Optional argument handling
  if (argc > 1) {
    rb_raise(rb_eArgError, "Wrong number of arguments (0..1)");
  }

  if (argc == 1) 
    cmd = argv[0];

  TypedData_Get_Struct(self, sysvmq_t, &sysvmq_type, sysv);

  // Default to IPC_STAT
  if (cmd == Qnil) {
    cmd = INT2FIX(IPC_STAT);
  }

  // TODO: Does FIX2INT actually perform this check already?
  Check_Type(cmd, T_FIXNUM);

  while (msgctl(sysv->id, FIX2INT(cmd), &info) < 0) {
    if (errno == EINTR) {
      rb_thread_wait_for(polling_interval);
      continue;
    }
    rb_sys_fail("Failed executing msgctl(2) command.");
  }

  // Map values from struct to a hash
  // TODO: Number of bytes, platform specific and not guaranteed on Darwin. Test
  // it on BSD with that.
  // TODO: Add all the fields
  // TODO: They are probably not ints..
  info_hash = rb_hash_new();
  rb_hash_aset(info_hash, ID2SYM(rb_intern("count")),         INT2FIX(info.msg_qnum));
  rb_hash_aset(info_hash, ID2SYM(rb_intern("maximum_bytes")), INT2FIX(info.msg_qbytes)); 

  // TODO: Can probably make a better checker here for whether the struct
  // actually has the member.
#ifdef __linux__
  rb_hash_aset(info_hash, ID2SYM(rb_intern("bytes")), INT2FIX(info.__msg_cbytes));
#elif __APPLE__
  rb_hash_aset(info_hash, ID2SYM(rb_intern("bytes")), INT2FIX(info.msg_cbytes));
#endif

  return info_hash;
}

static VALUE
sysvmq_destroy(VALUE self)
{
  VALUE argv[1];
  argv[0] = INT2FIX(IPC_RMID);
  return sysvmq_stats(1, argv, self);
}


// This is used for passing values between the `maybe_blocking` function and the
// Ruby function. There must be a better way.
typedef struct {
  int     size;
  int     flags;
  int     type;
  int     msg_size; // TODO: typelol
  VALUE*  self;
} 
sysvmq_blocking_call_t;

// Blocking call to msgsnd(2) (see sysvmq_send). This is to be called without
// the GVL, and must therefore not use any Ruby functions.
static void*
sysvmq_maybe_blocking_receive(void *data)
{
  sysvmq_t* sysv;
  sysvmq_blocking_call_t* arguments = (sysvmq_blocking_call_t*) data;
  TypedData_Get_Struct(*arguments->self, sysvmq_t, &sysvmq_type, sysv);

  while ((arguments->msg_size = msgrcv(sysv->id, sysv->msgbuf, sysv->buffer_size, arguments->type, arguments->flags)) < 0) {
    if (errno == EINTR) {
      rb_thread_wait_for(polling_interval);
      continue;
    }
    rb_sys_fail("Failed receiving message to the message queue.");
  }

  return NULL;
}

// ssize_t msgrcv(int msqid, void *msgp, size_t msgsz, long msgtyp, int msgflg);
// http://man7.org/linux/man-pages/man2/msgsnd.2.html
//
// Receive a message from the message queue.
VALUE
sysvmq_receive(VALUE self, VALUE type, VALUE flags)
{
  sysvmq_t* sysv;
  sysvmq_blocking_call_t blocking;
  VALUE message;

  TypedData_Get_Struct(self, sysvmq_t, &sysvmq_type, sysv);

  Check_Type(type, T_FIXNUM);
  Check_Type(flags, T_FIXNUM);

  // Attach blocking call parameters to the struct passed to the blocking
  // function wrapper.
  blocking.flags = FIX2INT(flags);
  blocking.type  = FIX2INT(type);
  blocking.self  = &self;

  // msgrcv(2) can block sending a message, if IPC_NOWAIT is not passed. 
  // We unlock the GVL waiting for the call so other threads (e.g. signal
  // handling) can continue to work. Sets `msg_size` on `blocking` with the size
  // of the message returned.
  rb_thread_call_without_gvl2(sysvmq_maybe_blocking_receive, &blocking, RUBY_UBF_IO, NULL);

  // Reencode as UTF-8 from ASCII
  message = rb_str_new(sysv->msgbuf->mtext, blocking.msg_size);
  return rb_funcall(message, rb_intern("force_encoding"), 1, rb_str_new2("utf-8"));
}

// Blocking call to msgsnd(2) (see sysvmq_send). This is to be called without
// the GVL, and must therefore not use any Ruby functions.
static void*
sysvmq_maybe_blocking_send(void *data)
{
  sysvmq_t* sysv;
  sysvmq_blocking_call_t* arguments = (sysvmq_blocking_call_t*) data;

  TypedData_Get_Struct(*arguments->self, sysvmq_t, &sysvmq_type, sysv);

  while (msgsnd(sysv->id, sysv->msgbuf, arguments->size, arguments->flags) < 0) {
    if (errno == EINTR) {
      rb_thread_wait_for(polling_interval);
      continue;
    }
    rb_sys_fail("Failed sending message to the message queue.");
  }

  return NULL;
}

// int msgsnd(int msqid, const void *msgp, size_t msgsz, int msgflg);
// http://man7.org/linux/man-pages/man2/msgsnd.2.html
//
// Sends a message to the message queue.
VALUE
sysvmq_send(VALUE self, VALUE message, VALUE priority, VALUE flags)
{
  sysvmq_blocking_call_t blocking;
  sysvmq_t* sysv;

  TypedData_Get_Struct(self, sysvmq_t, &sysvmq_type, sysv);

  Check_Type(flags, T_FIXNUM);
  Check_Type(priority, T_FIXNUM);
  message = rb_any_to_s(message);

  // Attach blocking call parameters to the struct passed to the blocking
  // function wrapper.
  blocking.flags = FIX2INT(flags);
  blocking.size  = RSTRING_LEN(message);
  blocking.self  = &self;

  // The buffer can be obtained from `sysvmq_maybe_blocking_send`, instead of
  // passing it, set it directly on the instance struct.
  sysv->msgbuf->mtype = FIX2INT(priority);

  // TODO: Can a string copy be avoided?
  strncpy(sysv->msgbuf->mtext, StringValueCStr(message), blocking.size);

  // msgsnd(2) can block waiting for a message, if IPC_NOWAIT is not passed. 
  // We unlock the GVL waiting for the call so other threads (e.g. signal
  // handling) can continue to work.
  rb_thread_call_without_gvl(sysvmq_maybe_blocking_send, &blocking, RUBY_UBF_IO, NULL);

  return message;
}

// int msgget(key_t key, int msgflg);
// http://man7.org/linux/man-pages/man2/msgget.2.html
//
// Instead of calling `msgget` method directly to get the `msgid` (the return
// value of `msgget`) from Rubyland and pass it around, it's stored internally
// in a struct only directly accessible from C-land. It's passed to all the
// other calls that require a `msgid`, for convienence and to share the buffer.
VALUE
sysvmq_initialize(VALUE self, VALUE key, VALUE buffer_size, VALUE flags)
{
  sysvmq_t* sysv;
  size_t msgbuf_size;

  // TODO: Also support string keys, so you can pass '0xDEADC0DE'
  Check_Type(key,   T_FIXNUM);
  Check_Type(flags, T_FIXNUM);
  Check_Type(buffer_size, T_FIXNUM);

  TypedData_Get_Struct(self, sysvmq_t, &sysvmq_type, sysv);

  // TODO: This probably doesn't hold on all platforms.
  sysv->key = FIX2LONG(key);

  while ((sysv->id = msgget(sysv->key, FIX2INT(flags))) < 0) {
    if (errno == EINTR) {
      rb_thread_wait_for(polling_interval); // TODO: Really necessary here?
      continue;
    }
    rb_sys_fail("Failed opening the message queue.");
  }

  // Allocate the msgbuf buffer once for the instance, to not allocate a buffer
  // for each message sent. This makes SysVMQ not thread-safe (requiring a
  // buffer for each thread), but is a reasonable trade-off for now for the
  // performance.
  sysv->buffer_size = FIX2INT(buffer_size);
  msgbuf_size = sysv->buffer_size * sizeof(char) + sizeof(long);

  // Note that this is a zero-length array, so we size the struct to size of the
  // header (long, the mtype) and then the rest of the space for message buffer.
  sysv->msgbuf = (sysvmq_msgbuf_t*) malloc(msgbuf_size);
  if (sysv->msgbuf == NULL) {
    rb_syserr_new(ENOMEM, "Ran out of memory allocating message buffer");
  }

  return self;
}

void Init_sysvmq()
{
  VALUE sysvmq = rb_define_class("SysVMQ", rb_cObject);

  // Waiting between blocking calls that have been interrupted outside the GVL,
  // this is to allow time for signal handlers to process signals.
  polling_interval.tv_sec  = 0;
  polling_interval.tv_usec = 5;

  // Define platform specific constants from headers
  rb_define_const(sysvmq, "IPC_CREAT",  INT2NUM(IPC_CREAT));
  rb_define_const(sysvmq, "IPC_EXCL",   INT2NUM(IPC_EXCL));
  rb_define_const(sysvmq, "IPC_NOWAIT", INT2NUM(IPC_NOWAIT));
  rb_define_const(sysvmq, "IPC_RMID",   INT2NUM(IPC_RMID));
  rb_define_const(sysvmq, "IPC_SET",    INT2NUM(IPC_SET));
  rb_define_const(sysvmq, "IPC_STAT",   INT2NUM(IPC_STAT));
  rb_define_const(sysvmq, "IPC_INFO",   INT2NUM(IPC_INFO));

  // Define the SysVMQ class and its methods
  rb_define_alloc_func(sysvmq, sysvmq_alloc);
  rb_define_method(sysvmq, "initialize", sysvmq_initialize, 3);
  rb_define_method(sysvmq, "send",       sysvmq_send,    3);
  rb_define_method(sysvmq, "receive",    sysvmq_receive, 2);
  rb_define_method(sysvmq, "stats",      sysvmq_stats,   -1);
  rb_define_method(sysvmq, "destroy",    sysvmq_destroy, 0);
}
