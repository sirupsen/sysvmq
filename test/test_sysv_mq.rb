#encoding:utf-8
require 'test_helper'
require 'timeout'

class SysVMQTest < MiniTest::Unit::TestCase
  def setup
    @mq = SysVMQ.new(0xDEADC0DE, size: 64)
  end

  def teardown
    @mq.destroy
  rescue
  end

  def test_send_and_receive_a_method
    @mq.send("Hello World")
    assert_equal "Hello World", @mq.receive
  end

  def test_send_and_receive_two_messages_in_order
    @mq.send("Hello 1")
    @mq.send("Hello 2")

    assert_equal "Hello 1", @mq.receive
    assert_equal "Hello 2", @mq.receive
  end

  def test_send_and_receive_utf8
    @mq.send("simån hørup")
    assert_equal "simån hørup", @mq.receive
  end

  def test_on_empty_queue_should_return_enomsg_if_ipc_nowait_is_set
    assert_raises Errno::ENOMSG do
      @mq.receive(flags: SysVMQ::IPC_NOWAIT)
    end
  end

  def test_fails_when_sending_a_message_too_big
    assert_raises Errno::E2BIG do
      @mq.send("B" * 100, flags: SysVMQ::IPC_NOWAIT)
    end
  end

  def test_sends_and_receives_message_of_exactly_buffer_size
    max = "B" * 64
    @mq.send(max)
    assert_equal max, @mq.receive
  end

  def test_destroy_removes_queue
  end

  def test_stats_returns_stats_about_queue
    stats = @mq.stats
    assert_equal 0, stats[:msg_qnum]
  end

  def test_count_returns_number_of_messages_in_queue
    assert_equal 0, @mq.count
    @mq.send("oemg")
    assert_equal 1, @mq.count
    @mq.receive
    assert_equal 0, @mq.count
  end

  def test_bytes_returns_number_of_bytes_in_queue
    assert_equal 0, @mq.bytes
    @mq.send("oemg")
    assert_equal 4, @mq.bytes
    @mq.receive
    assert_equal 0, @mq.bytes
  end

  def test_max_bytes_returns_max_bytes_in_queue
    assert_equal 2048, @mq.max_bytes
  end

  def test_destroy_the_queue
    @mq.destroy

    assert_raises Errno::EINVAL do
      @mq.stats
    end
  end

  def test_allow_multiple_queues_with_different_sizes
    @mq.send("B" * @mq.size)

    mq2 = SysVMQ.new(0xDEADCAFE, size: 128)
    mq2.send("B" * mq2.size)
    mq2.destroy
  end

  # def test_sends_and_receives_empty_message
  #   @mq.send("")
  #   assert_equal "", @mq.receive
  # end

  def test_on_empty_queue_should_block_but_not_block_the_vm
    # This would never terminate if it blocked the VM. libffi takes care of this
    # if blocking: true is passed to attach_function
    assert_raises Timeout::Error do
      Timeout.timeout(0.1) do
        @mq.receive
      end
    end
  end
end
