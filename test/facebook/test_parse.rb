
require 'rest-more/test'

describe RC::Facebook do

  should 'return nil if parse error, but not when call data directly' do
    rg = RC::Facebook.new
    rg.parse_cookies!({}).should.eq nil
    rg.data              .should.eq({})
  end

  should 'parse if fbs contains json as well' do
    algorithm = 'HMAC-SHA256'
    user      = '{"country"=>"us", "age"=>{"min"=>21}}'
    data      = {'algorithm' => algorithm, 'user' => user}
    rg        = RC::Facebook.new(:data => data, :secret => 'secret')
    sig       = rg.send(:calculate_sig, data)
    rg.parse_fbs!("\"#{rg.fbs}\"").should.eq data.merge('sig' => sig)
  end

  should 'extract correct access_token or fail checking sig' do
    access_token = '1|2-5|f.'
    app_id       = '1829'
    secret       = app_id.reverse
    sig          = '398262caea8442bd8801e8fba7c55c8a'
    fbs          = "access_token=#{RC::Middleware.escape(access_token)}&" \
                   "expires=0&secret=abc&session_key=def-456&sig=#{sig}&uid=3"

    check = lambda{ |token, fbs1|
      http_cookie =
        "__utma=123; __utmz=456.utmcsr=(d)|utmccn=(d)|utmcmd=(n); " \
        "fbs_#{app_id}=#{fbs1}"

      rg = RC::Facebook.new(:app_id => app_id, :secret => secret)
      rg.parse_rack_env!('HTTP_COOKIE' => http_cookie).
                      should.kind_of?(token ? Hash : NilClass)
      rg.access_token.should.eq token

      rg.parse_rack_env!('HTTP_COOKIE' => nil).should.eq nil
      rg.data.should.eq({})

      rg.parse_cookies!({"fbs_#{app_id}" => fbs1}).
                      should.kind_of?(token ? Hash : NilClass)
      rg.access_token.should.eq token

      rg.parse_fbs!(fbs1).
                      should.kind_of?(token ? Hash : NilClass)
      rg.access_token.should.eq token
    }
    check.call(access_token, fbs)
    check.call(access_token, "\"#{fbs}\"")
    fbs << '&inject=evil"'
    check.call(nil, fbs)
    check.call(nil, "\"#{fbs}\"")
  end

  should 'not pass if there is no secret, prevent from forgery' do
    rg = RC::Facebook.new
    rg.parse_fbs!('"feed=me&sig=bddd192cf27f22c05f61c8bea24fa4b7"').
      should.eq nil
  end

  should 'parse json correctly' do
    rg = RC::Facebook.new

    rg.parse_json!('bad json')    .should.eq nil
    rg.parse_json!('{"no":"sig"}').should.eq nil
    rg.parse_json!('{"feed":"me","sig":"bddd192cf27f22c05f61c8bea24fa4b7"}').
      should.eq nil

    rg = RC::Facebook.new(:secret => 'bread')
    rg.parse_json!('{"feed":"me","sig":"20393e7823730308938a86ecf1c88b14"}').
      should.eq({'feed' => 'me', 'sig' => "20393e7823730308938a86ecf1c88b14"})
    rg.data.empty?.should.eq false
    rg.parse_json!('bad json')
    rg.data.empty?.should.eq true
  end

  describe 'signed_request' do
    def encode str
      [str].pack('m').tr("\n=", '').tr('+/', '-_')
    end

    def setup_sr secret, data, sig=nil
      json_encoded = encode(RC::Json.encode(data))
      sig ||= OpenSSL::HMAC.digest('sha256', secret, json_encoded)
      "#{encode(sig)}.#{json_encoded}"
    end

    should 'parse invalid' do
      RC::Facebook.new.parse_signed_request!('bad').should.eq nil
    end

    should 'parse' do
      secret = 'aloha'
      rg = RC::Facebook.new(:secret => secret)
      rg.parse_signed_request!(setup_sr(secret, {'ooh' => 'dir',
                                                 'moo' => 'bar'}))
      rg.data['ooh'].should.eq 'dir'
      rg.data['moo'].should.eq 'bar'

      rg.parse_signed_request!(setup_sr(secret, {'ooh' => 'dir',
                                                 'moo' => 'bar'}, 'wrong')).
                                               should.eq nil
      rg.data                                 .should.eq({})
    end

    should 'fbsr and cookies with fbsr' do
      secret       = 'lulala'
      code         = 'lalalu'
      access_token = 'lololo'
      user_id      = 123
      app_id       = 456
      rg           = RC::Facebook.new(:secret => secret,
                                      :app_id => app_id)

      stub_request(:post, 'https://graph.facebook.com/oauth/access_token').
        with(:body => {'client_id' => '456', 'client_secret' => 'lulala',
                       'code' => 'lalalu', 'redirect_uri' => ''}).
        to_return(:body => 'access_token=lololo').times(2)

      check = lambda{
        rg.data['code']        .should.eq code
        rg.data['access_token'].should.eq access_token
        rg.data['user_id']     .should.eq user_id
      }

      rg.parse_fbsr!(setup_sr(secret, 'code' => code, 'user_id' => user_id))
      check.call
      rg.data = nil
      rg.data.should.eq({})

      rg.parse_cookies!("fbsr_#{app_id}" =>
        setup_sr(secret, 'code' => code, 'user_id' => user_id))
      check.call
    end
  end

  should 'generate correct fbs with correct sig' do
    RC::Facebook.new(:access_token => 'fake', :secret => 's').fbs.
      should.eq \
      "access_token=fake&sig=#{Digest::MD5.hexdigest('access_token=fakes')}"
  end

  should 'parse fbs from facebook response which lacks sig...' do
    rg = RC::Facebook.new(:access_token => 'a', :secret => 'z')
    rg.parse_fbs!(rg.fbs)                           .should.kind_of?(Hash)
    rg.data.empty?.should.eq false
    rg.parse_fbs!(rg.fbs.sub(/sig\=\w+/, 'sig=abc')).should.eq nil
    rg.data.empty?.should.eq true
  end

  should 'generate correct fbs with additional parameters' do
    rg = RC::Facebook.new(:access_token => 'a', :secret => 'z')
    rg.data['expires'] = '1234'
    rg.parse_fbs!(rg.fbs).should.kind_of?(Hash)
    rg.access_token      .should.eq 'a'
    rg.data['expires']   .should.eq '1234'
  end
end
