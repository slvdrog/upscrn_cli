['json/lib',
'rest_client/lib',
'jruby_openssl/lib',
'bouncy_castle_java/lib'].each do |lp|
  $LOAD_PATH << lp
  $LOAD_PATH << 'lib/ruby/' + lp
 end

