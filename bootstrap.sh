#!/usr/bin/env bash

# Colorful output
_red=`tput setaf 1`
_green=`tput setaf 2`
_orange=`tput setaf 3`
_blue=`tput setaf 4`
_purple=`tput setaf 5`
_cyan=`tput setaf 6`
_white=`tput setaf 6`
_reset=`tput sgr0`


# Log file
LOG_FILE=`mktemp`

# Global helpers
log()  { printf "${_green}%b${_reset}\n" "$*"; printf "\n%b\n" "$*" >> $LOG_FILE; }
logstdout() { printf "${_green}%b${_reset}\n" "$*" 2>&1 ; }
warn() { printf "${_orange}%b${_reset}\n" "$*"; printf "%b\n" "$*" >> $LOG_FILE; }
fail() { printf "\n${_red}ERROR: $*${_reset}\n"; printf "\nERROR: $*\n" >> $LOG_FILE; }

# check if root
# function check_root() {
#     if [[ $EUID -ne 0 ]]; then
#         echo "You must be root to execute this script"
#         exit 1
#     fi
# }

TOTAL=6

function setup() {
    mkdir -p ~/projects
    cd ~/projects
    sudo tee /etc/sudoers.d/$USER <<END
$USER $(hostname) =(ALL:ALL) NOPASSWD: ALL
END
    sudo tee -a /etc/hosts <<END
103.121.209.188 fonts.googleapis.com ajax.googleapis.com themes.googleusercontent.com fonts.gstatic.com
END
}

function teardown() {
    sudo /bin/rm /etc/sudoers.d/$USER
    sudo -k
}

function change_to_tuna_mirror() {
    wget https://tuna.moe/oh-my-tuna/oh-my-tuna.py

    # for Ubuntu apt source
    sudo python3 oh-my-tuna.py -g -y
    sudo apt-get update

    # for pypi
    mkdir -p $HOME/.config/pip
    touch $HOME/.config/pip

    log "[1/$TOTAL] mirror has been changed to tuna"
}

function install_gradle() {
    wget https://services.gradle.org/distributions/gradle-5.4.1-bin.zip
    mkdir /opt/gradle
    unzip -d /opt/gradle gradle-5.4.1-bin.zip
    echo 'export PATH="$PATH":/opt/gradle/gradle-5.4.1/bin' >> ~/.bashrc
    export PATH="$PATH":/opt/gradle/gradle-5.4.1/bin
}

function install_packages() {
    # build essentials
    sudo apt-get install -y build-essential git vim curl python-pip
    python3 $HOME/projects/oh-my-tuna.py

    # docker, from https://mirrors.tuna.tsinghua.edu.cn/help/docker-ce/
    sudo apt-get remove -y docker docker-engine docker.io
    sudo apt-get install -y apt-transport-https ca-certificates gnupg2 software-properties-common
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    sudo apt-get update
    sudo add-apt-repository \
        "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu \
        $(lsb_release -cs) \
        stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce
    pip install docker-compose

    # database deps
    sudo apt-get install -y mysql-server mysql-workbench libmysqlclient-dev libsqlite3-dev
    sudo apt-get install -y redis-server
    sudo systemctl enable redis-server
    sudo systemctl restart redis-server

    # ruby dependencies
    # NOTE: for ruby 2.2.2, must use libssl1.0-dev (an old version of libssl) on Ubuntu 18.04
    sudo apt-get install -y libssl1.0-dev libreadline-dev zlib1g-dev libgmp3-dev

    # packages below are for development
    # apt-get install -y git debconf-utils nodejs npm
    # apt-get install -y "openjdk-8*" maven
    sudo apt-get install -y openssh-server
    # install_gradle
    log "[2/$TOTAL] package installation done"
}

function install_rbenv() {
    # maybe use the ruby shipped with Ubuntu?
    # sudo apt-get install -y ruby ruby-bundler ruby-dev
    # rbenv
    git clone https://github.com/rbenv/rbenv.git ~/.rbenv
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.rbenv/bin:$PATH"
    echo 'eval "$(rbenv init -)"' >> ~/.bashrc
    eval "$(rbenv init -)"
    rbenv versions

    # rbenv-build
    mkdir -p ~/.rbenv/plugins
    git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

    # China mirror
    git clone git://github.com/AndorChen/rbenv-china-mirror.git ~/.rbenv/plugins/rbenv-china-mirror

    log "[3/$TOTAL] rbenv installation done"
}

function clone_sources() {
    # TODO: use github in the future
    
    # Tango
    # git clone https://github.com/autolab/Tango.git
    git clone https://gitee.com/kidolab/Tango.git

    # Autolab
    # git clone https://github.com/autolab/Autolab
    git clone https://gitee.com/kidolab/Autolab.git

    log "[4/$TOTAL] Autolab and Tango source code downloaded"
}

function install_ruby_binary() {
    wget -O /tmp/ruby-2.2.10.tar.bz2 "https://rvm.io/binaries/ubuntu/18.04/x86_64/ruby-2.2.10.tar.bz2"
    tar -xjf /tmp/ruby-2.2.10.tar.bz2 -C ~/.rbenv/versions/
    rbenv local ruby-2.2.10
    rbenv rehash
}

function install_ruby_compilation() {
    rbenv install $(cat .ruby-version)
    rbenv rehash
}

function config_autolab() {
    cd Autolab
    install_ruby_binary

    # China mirror
    gem sources --add https://gems.ruby-china.com/ --remove https://rubygems.org/
    bundle config mirror.https://rubygems.org https://gems.ruby-china.com

    # bundler
    gem install bundler -v '<=1.16.0'   # 1.16.0 has been tested, too high wont work
    rbenv rehash

    # gems
    cd bin
    bundle install

    cd ..
    # TODO: fix temp config
    tee config/database.yml <<END
# SQLite Configuration
development:
  adapter: sqlite3
  database: db/db.sqlite3
  pool: 5
  timeout: 5000
END
    cp config/school.yml.template config/school.yml
    cp config/initializers/devise.rb.template config/initializers/devise.rb

    # TODO: fix temp values
    sed -i "s/<YOUR-SECRET-KEY>/`bundle exec rake secret`/g" config/initializers/devise.rb
    sed -i "s/<YOUR_WEBSITE>/foo.bar/g" config/initializers/devise.rb

    # populate the database
    bundle exec rake db:create
    bundle exec rake db:migrate
    bundle exec rake autolab:populate
    # bundle exec rails s -p 3000

    cd ..
    log "[5/$TOTAL] Autolab configured successfully"
}

function config_tango() {
    cd Tango
    cp config.template.py config.py
    mkdir courselabs
    pip install virtualenv
    echo 'PATH=$PATH:$HOME/.local/bin' >> $HOME/.bashrc
    export PATH=$PATH:$HOME/.local/bin
    virtualenv .
    source bin/activate
    pip install -r requirements.txt
    mkdir volumes
    log "[6/$TOTAL] Tango configured successfully"
}

function finish() {
    logstdout "Autolab has been successfully set up"
    logstdout 'Run `RESTFUL_HOST=localhost RESTFUL_PORT=3000 RESTFUL_KEY=test bundle exec rails s -p 8000` to start the Autolab server at port 8000'
    logstdout 'Run `python restful-tango/server.py 3000` to start the Tango server at port 3000'
    logstdout 'Run `python jobManager.py` to start the Tango consumer'
    # logstdout 'Open a terminal and run `` to'
}

setup
change_to_tuna_mirror
install_packages
install_rbenv
clone_sources
config_autolab
config_tango
teardown
finish
