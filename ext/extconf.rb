require 'mkmf'

have_header 'sys/ipc.h'
have_header 'sys/msg.h'
have_header 'sys/types.h'

have_func 'rb_thread_blocking_region'
have_func 'rb_thread_call_without_gvl'

create_makefile 'sysvmq'
