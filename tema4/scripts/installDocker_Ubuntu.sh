
########## INSTALL DOCKER ENGINE

# Update package information, ensure that APT works with the https method, and that CA certificates are installed.
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates

# Add the new GPG key to the adv keychain. (For more info, see the output of man apt-key.)
sudo apt-key adv \
               --keyserver hkp://ha.pool.sks-keyservers.net:80 \
               --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

# Obtain the codename of the used Ubuntu version
ubu_version=$(lsb_release -c | cut -f 2)

if [ "$ubu_version" = "precise" ]; then
  echo "You must upgrade your Linux kernel to the 3.13 version or newer to use Docker"
  exit 1
fi

# This determines where APT will search for Docker packages.
echo "deb https://apt.dockerproject.org/repo ubuntu-$ubu_version main" | sudo tee /etc/apt/sources.list.d/docker.list

# Update the APT package index.
sudo apt-get update

# Install the prerequisite packages for Ubuntu 16.04 Xenial
sudo apt-get install linux-image-extra-$(uname -r) linux-image-extra-virtual

# Install Docker.
sudo apt-get install docker-engine

# Start the docker daemon.
sudo service docker start

# Verify that docker is installed correctly by running the hello-world image.
#   (This command downloads a test image and runs it in a container.
#   When the container runs, it prints an informational message and exits.)
sudo docker run hello-world


########## INSTALL DOCKER COMPOSE

# For this project, we will also need Docker Compose, a tool for defining
# and running multi-container Docker applications. With Compose, we configure
# our app's services in a file and the create and start them with a single command.

# Install Docker Compose with curl
sudo curl -L "https://github.com/docker/compose/releases/download/1.9.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Apply executable permissions to the binary
sudo chmod +x /usr/local/bin/docker-compose

# Test the installation
sudo docker-compose --version

# Also, you can install the useful Command Completion add-on following the
# instructions on this page: https://docs.docker.com/compose/completion/
