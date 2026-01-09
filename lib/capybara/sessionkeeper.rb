require 'capybara'
require "capybara/sessionkeeper/version"
require 'date'
require 'json'
require 'time'
require 'yaml'

module Capybara
  module Sessionkeeper
    class CookieError < StandardError; end

    def save_cookies(path = nil)
      path = prepare_path(path, cookie_file_extension)
      data = cookies_to_json
      File.open(path, 'w') {|f| f.puts(data) }
      path
    end

    def restore_cookies(path = nil)
      path ||= find_latest_cookie_file
      return nil if path.nil?
      data = File.open(path, 'rb', &:read)
      restore_cookies_from_data(data)
    end

    def restore_cookies_from_data(data, options = {})
      raise CookieError, "visit must be performed to restore cookies" if ['data:,', 'about:blank'].include?(current_url)
      cookies = if %w[yml yaml].include?(options[:format])
                  load_yaml_cookies(data)
                else
                  JSON.parse(data)
                end
      cookies = normalize_cookie_keys(cookies)
      cookies.each do |d|
        begin
          driver.browser.manage.delete_cookie d[:name]
          driver.browser.manage.add_cookie d
        rescue StandardError => e
          skip_invalid_cookie_domain_error(e)
        end
      end
      driver.browser.manage.all_cookies
    end

    def cookies_to_yaml
      YAML.dump driver.browser.manage.all_cookies
    end

    def cookies_to_json
      cookies = driver.browser.manage.all_cookies
      JSON.generate(cookies.map {|cookie| normalize_cookie_for_json(cookie) })
    end

    def cookie_file_extension
      'cookies.json'
    end

    def find_latest_cookie_file
      Dir.glob(File.join([Capybara.save_path, "*.#{cookie_file_extension}"].compact)).max_by{|f| File.mtime(f) }
    end

    def skip_invalid_cookie_domain_error(error)
      if error.message =~ /invalid cookie domain/ || # Chrome
         error.message =~ /InvalidCookieDomainError/ || # Old firefox
         error.class.to_s == 'Selenium::WebDriver::Error::InvalidCookieDomainError' # Firefox
        # puts error.class, error.message
        # puts "Skipped invalid cookie domain: #{d[:domain]} - #{d.inspect}"
      else
        raise(error)
      end
    end

    def normalize_cookie_keys(cookies)
      Array(cookies).map do |cookie|
        cookie.each_with_object({}) do |(key, value), result|
          key = key.to_sym
          if %i[expires expiry].include?(key)
            value = normalize_cookie_expiration(value)
          end
          result[key] = value
        end
      end
    end

    def normalize_cookie_for_json(cookie)
      cookie.each_with_object({}) do |(key, value), result|
        key = key.to_s
        if %w[expires expiry].include?(key)
          result[key] = normalize_cookie_expiration(value)
        else
          result[key] = value
        end
      end
    end

    def normalize_cookie_expiration(value)
      return nil if value.nil?
      return value.to_time.to_i if value.is_a?(Time) || value.is_a?(DateTime)
      return value.to_i if value.is_a?(Integer)
      return Time.parse(value).to_i if value.is_a?(String)
      return value.to_i if value.respond_to?(:to_i)
      value
    end

    def load_yaml_cookies(data)
      if YAML.respond_to?(:safe_load)
        YAML.safe_load(
          data,
          permitted_classes: [DateTime, Time, Symbol],
          permitted_symbols: [],
          aliases: true
        )
      else
        YAML.load(data)
      end
    end
  end
end

Capybara::Session.include Capybara::Sessionkeeper
