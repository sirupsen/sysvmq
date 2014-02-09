#!/bin/bash

apt-get update

# Install chruby
if ! type -p chruby; then
  wget -O chruby-0.3.8.tar.gz https://github.com/postmodern/chruby/archive/v0.3.8.tar.gz
  tar -xzvf chruby-0.3.8.tar.gz
  cd chruby-0.3.8/
  sudo make install
  cat << EOF > /etc/profile.d/chruby.sh
if [ -n "\$BASH_VERSION" ] || [ -n "\$ZSH_VERSION" ]; then
  source /usr/local/share/chruby/chruby.sh
  source /usr/local/share/chruby/auto.sh
  chruby ruby # latest stable
fi
EOF
fi

# Install ruby-install
if ! type -p ruby-install; then
  wget -O ruby-install-0.3.4.tar.gz https://github.com/postmodern/ruby-install/archive/v0.3.4.tar.gz
  tar -xzvf ruby-install-0.3.4.tar.gz
  cd ruby-install-0.3.4/
  sudo make install
fi

# Install stable Rubby
if [ ! -d /opt/rubies/ruby-2.1.0 ]; then
  ruby-install ruby-2.1.0
fi
