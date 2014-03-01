require_relative 'test_helper'

class SysVMQTest < MiniTest::Unit::TestCase
  def setup
    @size = 1024
    @mq = SysVMQ.new(0xDEADC0DE, @size, SysVMQ::IPC_CREAT | 0666)
  end

  def teardown
    @mq.destroy
  end

  def test_send_message
    @mq.send("Hello world")
  end

  def test_send_and_receive_message
    message = "Hello World"
    @mq.send message
    assert_equal message, @mq.receive
  end

  def test_send_and_count_message
    @mq.send "test"
    assert_equal 1, @mq.stats[:count]
    @mq.send "test"
    assert_equal 2, @mq.stats[:count]
  end

  def test_send_and_receive_many_times
    many = 100_000
    message = "Hello World"

    many.times do
      @mq.send message
      assert_equal message, @mq.receive
    end
  end

  def test_sends_and_receives_utf8
    message = "simån hørup"
    @mq.send message
    assert_equal message, @mq.receive
  end

  def test_sending_5_bytes_should_report_5_byte_queue
    message = "B" * 5
    @mq.send message
    assert_equal 5, @mq.stats[:size]
  end

  def test_sending_utf_should_report_correct_size_queue
    message = "ø" * 5
    @mq.send message
    assert_equal "ø".bytes.size * 5, @mq.stats[:size]
  end

  def test_receive_on_empty_queue_raises_enomsg_if_ipc_nowait
    assert_raises Errno::ENOMSG do
      @mq.receive(0, SysVMQ::IPC_NOWAIT)
    end
  end

  def test_send_and_receive_empty_message
    @mq.send ""
    assert_equal "", @mq.receive
  end

  def test_allow_multiple_queues_with_different_sizes
    mq2 = SysVMQ.new(0xDEADCAFE, 2048, SysVMQ::IPC_CREAT | 0660)
    mq2.send("B" * 2048)
    mq2.destroy
  end

  def test_send_and_receive_with_type
    @mq.send("10", 10)
    @mq.send("5", 5)

    assert_equal "5", @mq.receive(5)
    assert_equal "10", @mq.receive(10)
  end

  def test_send_and_receive_with_negative_type
    @mq.send("10", 10)
    @mq.send("5", 5)

    assert_equal "5", @mq.receive(-7)
    assert_equal "10", @mq.receive(-10)
  end

  def test_responds_to_sigint
    pid = fork {
      begin
        mq = SysVMQ.new(0xDEADCAFE, 2048, SysVMQ::IPC_CREAT | 0660)
        mq.receive
      rescue Interrupt
        mq.destroy
      end
    }
    sleep 0.01
    Process.kill(:SIGINT, pid)
    Process.wait(pid)
  end

  def test_kills_thread_cleanly
    thread = Thread.new {
      mq = SysVMQ.new(0xDEADCAFE, 2048, SysVMQ::IPC_CREAT | 0660)
      mq.receive
    }

    sleep 0.01
    thread.kill
  end

  def test_nonblocking_send_and_receive
    message = "Hello World"
    @mq.send(message, 1, SysVMQ::IPC_NOWAIT)
    assert_equal message, @mq.receive(0, SysVMQ::IPC_NOWAIT)
  end

  def test_string_key_and_gc
    assert_raises TypeError do
      SysVMQ.new("0xDEADC0DE", @size, SysVMQ::IPC_CREAT | 0666)
    end
  end
end
