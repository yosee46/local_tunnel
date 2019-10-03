require "socket"

module Client
  class Tunnel
    attr_accessor :socket, :mutex, :busy, :last_pinged, :local_host_client

    CONNECTION_DEADL_IN_SEC = 20

    def initialize(socket, local_host_client)
      @socket = socket
      @local_host_client = local_host_client
      @mutex = Mutex.new
      @busy = false
    end

    def fileno
      @socket.fileno
    end

    def puts(data)
      @socket.puts(data)
    end

    def close
      @socket.close
    end

    def closed?
      @socket.closed?
    end

    def ping_timestamp
      @last_pinged = Time.now
    end

    def heartbeat(&func)
      return if closed?
      Utils.log.debug("start ping process")
      @mutex.synchronize do
        begin
          if @last_pinged.nil? || @last_pinged + CONNECTION_DEADL_IN_SEC > Time.now
            Utils.log.debug("ping request")
            puts("ping")
            return
          end
        rescue StandardError => e
          Utils.log.error(e.message)
          Utils.log.error(e.backtrace)
        end

        func.call
      end
    end

    def proxy (input)
      datas = []
      begin
        Utils.log.debug("start tunnel proxy")
        Utils.log.debug(input)
        Utils.log.debug(@local_host_client.inspect)
        @local_host_client.write(input)

        # I do not know why IO.select makes this code slower
        while buffer = @local_host_client.gets
          p buffer
          if buffer.nil?
            break
          end
          datas << buffer
        end
        Utils.log.debug("get data in tunnel proxy")
      rescue StandardError => e
        Utils.log.error(e.message)
        Utils.log.error(e.backtrace)
        @local_host_client.close
      end
      data = datas.join
      Utils.log.debug(data)
      puts(data)
    end

    def dispatch(&func)
      begin
        @busy = true
        @mutex.synchronize do
          return if closed?

          datas = []
          while IO.select([@socket], nil, nil, 1)
            datas << @socket.gets
          end
          next if datas.empty?
          data = datas.join
          Utils.log.debug(data)

          if data.chomp == "pong"
            ping_timestamp
            Utils.log.debug("accept pong")
          else
            if data.start_with?("pong")
              ping_timestamp
              data.slice!(0, 5)
            elsif data.end_with?("pong\n")
              ping_timestamp
              data.slice!(data.size - 5, 5)
            end

            Utils.log.debug("reformatted data")
            Utils.log.debug(data)

            func.call(data)
          end
        end
      ensure
        @busy = false
      end
    end

  end
end

