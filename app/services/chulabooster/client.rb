require "net/http"
require "json"

module Chulabooster
  class Error < StandardError; end
  class AuthError < Error; end        # 401
  class PermissionError < Error; end  # 403
  class RequestError < Error; end     # other 4xx / exhausted retries

  class Client
    EXPORT_ENTITIES = %w[programs courses students student_courses program_courses].freeze
    BASE_PATH    = "/api/ext/export"
    PAGE_SIZE    = 500
    RETRY_COUNT  = 3
    RETRY_DELAY  = 2
    OPEN_TIMEOUT = 8
    READ_TIMEOUT = 180  # student_courses is ~26s/request

    def initialize(config: Rails.application.credentials.chulabooster)
      @base_url   = config.fetch(:base_url)
      @app_id     = config.fetch(:app_id)
      @app_secret = config.fetch(:app_secret)
    end

    def each_page(entity, changed_since: nil, start_cursor: nil)
      validate!(entity)
      cursor = start_cursor
      loop do
        page = fetch_page(entity, cursor: cursor, changed_since: changed_since)
        yield page.fetch(entity), page["next_cursor"]
        cursor = page["next_cursor"]
        break if cursor.nil?
      end
    end

    def each_row(entity, **opts)
      each_page(entity, **opts) { |rows, _cursor| rows.each { |r| yield r } }
    end

    private

    def validate!(entity)
      EXPORT_ENTITIES.include?(entity) or raise ArgumentError, "unknown entity #{entity.inspect}"
    end

    def fetch_page(entity, cursor:, changed_since:)
      params = { limit: PAGE_SIZE }
      params[:cursor] = cursor if cursor
      params[:changed_since] = changed_since if changed_since
      uri = URI("#{@base_url}#{BASE_PATH}/#{entity}")
      uri.query = URI.encode_www_form(params)

      req = Net::HTTP::Get.new(uri)
      req["DeeAppId"] = @app_id
      req["DeeAppSecret"] = @app_secret

      attempt = 0
      begin
        attempt += 1
        code, body = perform(req, uri)
        case code
        when 200 then return JSON.parse(body)
        when 401 then raise AuthError, "ChulaBooster 401 (bad credentials)"
        when 403 then raise PermissionError, "ChulaBooster 403: #{body.to_s[0, 200]}"
        when 400..499 then raise RequestError, "ChulaBooster #{code}: #{body.to_s[0, 200]}"
        else raise RequestError, "ChulaBooster #{code}"
        end
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, RequestError => e
        raise if e.is_a?(RequestError) && attempt > RETRY_COUNT
        if attempt <= RETRY_COUNT
          sleep(RETRY_DELAY)
          retry
        end
        raise RequestError, "ChulaBooster #{entity} failed after #{attempt} attempts: #{e.message}"
      end
    end

    # Seam for tests (override via define_singleton_method). Real impl does the HTTP GET.
    def perform(request, uri)
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
      [res.code.to_i, res.body.to_s]
    end
  end
end
