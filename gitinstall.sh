#!/bin/bash
# Setup file for configuring git + gitolite + git-daemon + gitweb for headless 
# setup.

read -p "Git user.name: " username
read -p "Git user.email: " useremail

# git setup

# Install git and doc:
sudo apt-get -y install git-core git-doc

# Setup your username and email:
git config --global user.name "$username"
git config --global user.email $useremail


# apache install
sudo apt-get -y install apache2


# gitolite setup

# gitolite uses ssh keys to manage access to the git repositories.
# In the following steps, we set up gitolite to initialize its admin repository
# with your public key.

# Copy over your pubkey from your local machine to the git server
while [ ! -f /tmp/$username.pub ]
do
    read -p "Copy over your pubkey ($username.pub) to /tmp/..."
done

# Create gitolite group and gitolite user:
sudo addgroup gitolite
sudo adduser --gecos "gitolite" --disabled-password --home /home/gitolite --ingroup gitolite gitolite

# Install gitolite:
sudo apt-get -y install gitolite

# Append www-data to gitolite group so gitweb can access the repos:
sudo usermod -a -G gitolite www-data

# and make sure that groups are updated for apache:
sudo service apache2 restart

# Run the gitolite setup:
sudo su gitolite -c "gl-setup -q /tmp/$username.pub"

# Setup will allow you to modify gitolite config umask settings so that
# new repos are given permissions to enable gitweb and git-daemon export:
# change $REPO_UMASK = 0077; to $REPO_UMASK = 0027; # gets you 'rwxr-x---'
sudo su gitolite -c "sed -i 's/\$REPO_UMASK = 0077/\$REPO_UMASK = 0027/g' /home/gitolite/.gitolite.rc"
sudo su gitolite -c 'chmod g+r /home/gitolite/projects.list'
sudo su gitolite -c 'chmod -R g+rx /home/gitolite/repositories'

STRING=$( cat <<EOF
You should now be able to clone the gitolite-admin.git repository that.s created automatically by the gitolite setup script:\n\n

# FROM YOUR LOCAL MACHINE\n
git clone gitolite@git.server:gitolite-admin.git\n\n

Edit gitolite.conf to enable gitweb and git-daemon export for testing:\n\n

# FROM YOUR LOCAL MACHINE\n
cd gitolite-admin\n
emacs conf/gitolite.conf\n
# change to:\n
repo    testing\n
      RW+     =   @all\n
      R       =   daemon\n
testing "Owner" = "Test repo"\n
git add conf/gitolite.conf\n
git commit -m "Enabled gitweb and git-daemon export for testing repo"\n
git push\n
cd ..\n\n

Setting the repo owner and description automatically gives read access to gitweb so you don.t have to specify it explicitly.\n\n

Clone testing and add a file (so it.s not empty):\n\n

git clone gitolite@git.server:testing.git\n
cd testing\n
echo "README" > README\n
git add README\n
git commit -m "Added README"\n
git push origin master\n
EOF
)
echo -e $STRING

set flag=""
while [ "$flag" != "cont" ]
do
    read -p "Type 'cont' to continue: " flag
done


# gitweb setup

#Install gitweb:
sudo apt-get -y install highlight gitweb

# Change the gitweb configuration to use the gitolite repo paths:
sudo sed -i 's/\/var\/cache\/git/\/home\/gitolite\/repositories/g' /etc/gitweb.conf
sudo sed -i 's/#\$projects_list = $projectroot/\$projects_list = "\/home\/gitolite\/projects\.list"/g' /etc/gitweb.conf

STRING=$( cat <<EOF
Now you should be able to see the testing repository in gitweb at:\n
http://git.server/gitweb/
EOF
)
echo -e $STRING

set flag=""
while [ "$flag" != "cont" ]
do
    read -p "Type 'cont' to continue: " flag
done


# git-daemon setup

sudo apt-get -y install git-daemon-run

# Now we need to change the sv config for git-daemon so that it runs
# as the gitdaemon user and gitolite group (since gitolite group has
# read access to the repositories)
sudo sed -i 's/exec chpst -ugitdaemon/exec chpst -ugitdaemon:gitolite/g' /etc/sv/git-daemon/run
sudo sed -i 's/--base-path=\/var\/cache \/var\/cache\/git/--base-path=\/home\/gitolite\/repositories \/home\/gitolite\/repositories/g' /etc/sv/git-daemon/run

# Restart git-daemon:
sudo sv restart git-daemon

STRING=$( cat <<EOF
You should now be able to clone the testing repo via the git protocol:\n
git clone git://git.server/testing.git
EOF
)
echo -e $STRING

set flag=""
while [ "$flag" != "cont" ]
do
    read -p "Type 'cont' to continue: " flag
done

# Pretty URLs

# To enable pretty gitweb urls (http://git.server instead of 
# http://git.server/gitweb/ as explained in
# http://repo.or.cz/w/alt-git.git?a=blob_plain;f=gitweb/README):

# Open /etc/apache2/conf.d/gitweb and comment out everything
sed -i '/Alias \/gitweb/,/<\/Directory>/s/^/#/' /etc/apache2/conf.d/gitweb

# Enable rewrites in apache:
sudo a2enmod rewrite
sudo service apache2 restart

# Add a new .git. virtual host:
sudo cp ./gitvhost /etc/apache2/sites-available/git

# Enable the new .git. virtual host:
sudo a2ensite git
sudo a2dissite default
sudo service apache2 reload


# gitweb extras

# To enable other optional features of gitweb, add the following:
cat ./gitextras | sudo tee -a /etc/gitweb.conf > /dev/null


# Custom Theme

# To add a customized theme (from http://kogakure.github.com/gitweb-theme/):
if [ ! -d "/tmp/gitweb-theme" ]; then
    sudo mv /usr/share/gitweb/static/gitweb.js /usr/share/gitweb/static/gitweb.js.orig
    sudo mv /usr/share/gitweb/static/gitweb.css /usr/share/gitweb/static/gitweb.css.orig
    git clone git://github.com/kogakure/gitweb-theme.git /tmp/gitweb-theme
    sudo cp /tmp/gitweb-theme/gitweb.css /tmp/gitweb-theme/gitweb.js /usr/share/gitweb/static/
fi
