# sysvmq

`sysvmq` is a C extension that wraps SysV IPC Message Queues. 

Currently known to work on:

* Linux (MRI >= 2.0)

## Installation

Add `sysvm` to your Gemfile.

  gem 'sysvmq'

## Usage

```ruby
# Create a message queue with a 1024 byte buffer.
require 'sysvmq'
mq = SysVMQ.new(0xDEADC0DE, 1024, SysVMQ::IPC_CREAT | 0666)

mq.send "Hellø Wårld!"
assert_equal 1, mq.stats[:count]

assert_equal "Hellø Wårld!", mq.receive

# Raise an exception instead of blocking until a message is available
mq.receive(0, SysVMQ::IPC_NOWAIT)

ensure
# Delete queue
mq.destroy
```

