require 'pry'
require 'ffi'

class SysVMQ
  IPC_PRIVATE = 0x00000000
  IPC_CREAT   = 0x00000200
  IPC_EXCL    = 0x00000400
  IPC_NOWAIT  = 0x00000800
  IPC_STAT    = 2
  IPC_RMID    = 0

  class Buffer < FFI::Struct
  end

  # Comes from gepping with /typedef.*<type>;/ in /usr/local/include since
  # libffi only knows about the types from https://github.com/ffi/ffi/wiki/Types
  class Stats < FFI::Struct
    class Permissions < FFI::Struct
      layout cuid:  :uint32, # uid_t
             cgid:  :uint32, # gid_t
             uid:   :uint32, # uid_t
             gid:   :uint32, # gid_t
             mode:  :uint16, # mode_t
             _seq:  :ushort,
             _key:  :int32   # key_t
    end

    layout  msg_perm:   Permissions,
            msg_first:  :int32, 
            msg_last:   :int32,

            msg_cbytes: :ulong, # msglen_t,
            msg_qnum:   :ulong, # msgqnum_t,
            msg_qbytes: :ulong, # msglen_t,

            msg_lspid:  :int32, # pid_t,
            msg_lrpid:  :int32, # pid_t,

            msg_stime:  :long,  # time_t
            msg_pad1:   :int32,

            msg_rtime:  :long,  # time_t
            msg_pad2:   :int32,

            msg_ctime:  :long,  # time_t
            msg_pad3:   :int32,
            msg_pad4:   [:int32, 4]
  end

  module Raw
    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    attach_function :msgget, [ 
      :uint32, # key_t
      :int 
    ], :int

    attach_function :msgrcv, [ 
      :int, 
      :pointer, 
      :size_t, 
      :long, 
      :int 
    ], :int, blocking: true

    attach_function :msgsnd, [
      :int, 
      :pointer, 
      :size_t,
      :int 
    ], :int, blocking: true

    attach_function :msgctl, [ 
      :int, 
      :int,
      :pointer
    ], :int
  end

  attr_reader :id, :size, :key

  def initialize(key, mode: 0660, size: 1024, flags: IPC_CREAT)
    @key  = key
    @id   = Raw.msgget(key, mode | flags)
    @size = size

    # This struct changes depending on the size passed in. We must allocate this
    # size for the struct, so we ghetto-pass it.
    Buffer.class_eval do
      layout mtype: :long,
             mtext: [:uint8, size + 1] # +1 for null byte
    end

    @buffer = Buffer.new
  end

  def receive(type: 0, flags: 0)
    length = Raw.msgrcv(id, @buffer.pointer, @size, type, flags)

    if length < 0
      raise SystemCallError.new("Error reading from queue #{@key}", FFI::LastError.error)
    else
      @buffer[:mtext].to_a[0..length - 1].pack("C*").force_encoding("UTF-8")
    end
  end

  def stats
    stats = Stats.new
    stats[:msg_perm]  = Stats::Permissions.new

    error = Raw.msgctl(id, IPC_STAT, stats.pointer)

    if error < 0
      raise SystemCallError.new("Error getting message queue stats for #{@key}", FFI::LastError.error)
    else
      stats
    end
  end

  def count
    stats[:msg_qnum]
  end

  # For OS X, this is not guaranteed to be meaningful.
  # See /usr/include/sys/msg.h for reference.
  def bytes
    stats[:msg_cbytes]
  end

  def max_bytes
    stats[:msg_qbytes]
  end

  def destroy
    stats = Stats.new
    stats[:msg_perm]  = Stats::Permissions.new

    error = Raw.msgctl(id, IPC_RMID, stats.pointer)

    if error < 0
      raise SystemCallError.new("Error deleting message queue stats for #{@key}", FFI::LastError.error)
    else
      true
    end
  end

  def send(message, flags: 0, type: 1)
    if message.size > @size
      raise Errno::E2BIG.new("Message is bigger than buffer of #{@size} bytes.")
    end

    @buffer[:mtype] = type
    @buffer[:mtext] = message
    error = Raw.msgsnd(id, @buffer.pointer, message.bytes.size, flags)

    if error < 0
      raise SystemCallError.new("Error sending message to queue #{@key}", FFI::LastError.error)
    else
      true
    end
  end
end
