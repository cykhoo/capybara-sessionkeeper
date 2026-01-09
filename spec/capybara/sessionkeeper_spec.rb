require "spec_helper"

RSpec.describe Capybara::Sessionkeeper do
  it "has a version number" do
    expect(Capybara::Sessionkeeper::VERSION).not_to be nil
  end

  describe '#save_cookies' do
    it "saves cookies into file" do
      session.visit 'https://github.com/'
      path = session.save_cookies
      expect(path).to match(/capybara-\d+.cookies.json/)
    end

    it "saves cookies into specified file" do
      cookie_path = 'my/cookie.json'
      session.visit 'https://github.com/'
      session.save_cookies(cookie_path)
      expect(File).to be_exist(File.join(Capybara.save_path, cookie_path))
    end

    it "saves cookies without error when visit has never performed" do
      path = session.save_cookies
      expect(path).to match(/capybara-\d+.cookies.json/)
    end
  end

  describe '#restore_cookies' do
    context "when path of cookie file isn't given" do
      let(:save_path_for_test) { 'spec/fixtures/restore_test' }

      it "restores cookies from the latest file" do
        allow(Capybara).to receive(:save_path).and_return(save_path_for_test)
        session.visit 'https://github.com/'
        cookies = session.restore_cookies
        expect(cookies).not_to be_nil
        expect(cookies).to be_all{|c| c[:domain] =~ /github\.com/ }
      end

      it "returns nil when cookie file doesn't exist in save_path" do
        allow(Capybara).to receive(:save_path).and_return('spec/fixtures/not_exist')
        session.visit 'https://github.com/'
        expect(session.restore_cookies).to be_nil
      end
    end

    context 'when cookie file exists' do
      let(:cookie_path) { 'spec/fixtures/github.cookies.json' }

      it "restores cookies from file" do
        expect(session.driver.browser.manage.all_cookies).to be_empty
        session.visit 'https://github.com/'
        cookies = session.restore_cookies(cookie_path)
        expect(cookies).not_to be_empty
        expect(cookies).to be_all{|c| c[:domain] =~ /github\.com/ }
      end

      it "skips invalid domain error" do
        expect(session.driver.browser.manage.all_cookies).to be_empty
        session.visit 'https://www.google.com/'
        expect{
          session.restore_cookies(cookie_path)
        }.not_to raise_error
      end

      it "raises error when visit has never been performed" do
        expect{
          session.restore_cookies(cookie_path)
        }.to raise_error(Capybara::Sessionkeeper::CookieError, /visit/)
      end
    end
  end

  describe '#restore_cookies_from_data' do
    it "supports loading from yaml data" do
      session.visit 'https://github.com/'
      yaml_str = session.cookies_to_yaml

      cookies = session.restore_cookies_from_data(yaml_str, format: 'yaml')
      expect(cookies).not_to be_empty
      expect(cookies).to be_all{|c| c[:domain] =~ /github\.com/ }
      expect(session.driver.browser.manage.all_cookies).not_to be_empty
    end

    it "supports loading from json data" do
      session.visit 'https://github.com/'
      json_str = session.cookies_to_json

      cookies = session.restore_cookies_from_data(json_str, format: 'json')
      expect(cookies).not_to be_empty
      expect(cookies).to be_all{|c| c[:domain] =~ /github\.com/ }
      expect(session.driver.browser.manage.all_cookies).not_to be_empty
    end
  end

  describe '#cookies_to_yaml' do
    it "outputs string of yaml format" do
      session.visit 'https://github.com/'
      yaml_str = session.cookies_to_yaml
      data = if YAML.respond_to?(:safe_load)
               YAML.safe_load(
                 yaml_str,
                 permitted_classes: [DateTime, Time, Symbol],
                 permitted_symbols: [],
                 aliases: true
               )
             else
               YAML.load(yaml_str)
             end
      expect(data.map{|d| d[:domain] }).to include('github.com')
    end
  end

  describe '#cookies_to_json' do
    it "outputs string of json format" do
      session.visit 'https://github.com/'
      json_str = session.cookies_to_json
      data = JSON.parse(json_str)
      expect(data.map{|d| d['domain'] }).to include('github.com')
    end
  end

  describe '#find_latest_cookie_file' do
    it "works when Capybara.save_path is nil" do
      allow(Capybara).to receive(:save_path).and_return(nil)
      expect{
        session.find_latest_cookie_file
      }.not_to raise_error
    end
  end

  context 'with keeping session' do
    def app_host
      ENV.fetch('APP_HOST', 'https://testapp-capybara-sessionkeeper.herokuapp.com/')
    end

    it "sees the value in session after restoring cookies" do
      skip("Skipping on CI") if ENV['CI']
      session.visit "#{app_host}?test=abc"
      unless session.has_content?('Session: abc')
        skip("Test app unavailable")
      end
      expect(session).to have_content('Session: abc')
      session.save_cookies

      session.reset_session!

      session.visit app_host
      expect(session).to have_content('No Session')

      session.restore_cookies

      session.visit session.current_url
      expect(session).to have_content('Session: abc')
    end
  end
end
