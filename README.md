# sysvmq [![Build Status](https://travis-ci.org/Sirupsen/sysvmq.png?branch=v0.1.0)](https://travis-ci.org/Sirupsen/sysvmq)

`sysvmq` is a C extension that wraps System V IPC Message Queues. It's similar
to the [POSIX MQ Ruby wrapper](https://github.com/Sirupsen/posix-mqueue).
Message queues are handy for interprocess communication where you want to be
able to take down either endpoint easily. For example, a pipe or socket requires
you to implement handover logic in both applications. The main disadvantage of
SysV message queues over POSIX MQs (on Linux) is that SysV doesn't expose a file
descriptor to do e.g. `select(2)` on. The advantage of SysV is that it's
implemented on OS X, which POSIX MQs are not.

Note that `sysvmq` doesn't rely on any third-party message broker. The message
queue is handled by the kernel. It's extremely stable and performant.

`sysvmq` has been tested heavily in production at Shopify, under more than `100k
RPS` and is still in use as of Feb, 2020.

## Installation

Add `sysvmq` to your Gemfile.

`gem 'sysvmq'`

Currently known to work on Linux and OS X for MRI >= 1.9

## Usage

```ruby
# Create a message queue with a 1024 byte buffer.
require 'sysvmq'
mq = SysVMQ.new(0xDEADC0DE, 1024, SysVMQ::IPC_CREAT | 0666)

mq.send "Hellø Wårld!"
assert_equal 1, mq.stats[:count]

assert_equal "Hellø Wårld!", mq.receive.force_encoding("UTF-8")

# Raise an exception instead of blocking until a message is available
mq.receive(0, SysVMQ::IPC_NOWAIT)

ensure
# Delete queue
mq.destroy
```

## Proc settings

System V queues are limited by default to a maximum of 16 message queues, a maximum of 8KB per message, and a maximum of 16KB for the total size of all messages in a queue.

To increase (or decrease) these limits, either run:

```sh
sysctl -w kernel.msgmni=32
sysctl -w kernel.msgmax=1000000
sysctl -w kernel.msgmnb=2000000
```

or write to /etc/sysctl.conf:

```sh
echo 'kernel.msgmni=32' >> /etc/sysctl.conf # maximum number of message queues
echo 'kernel.msgmax=1000000' >> /etc/sysctl.conf # maximum number of bytes per message
echo 'kernel.msgmnb=2000000' >> /etc/sysctl.conf # maximum total size of all messages in a queue
sysctl -p
```

See http://man7.org/linux/man-pages/man5/proc.5.html for more information.

## Todo

* Explain messages types
* Add named params for flags (e.g. `mq.receive(:front, blocking: false)`)
  instead of ORing flags directly.
* Add `IPC_INFO` on Linux
* Add all of `IPC_STAT`
