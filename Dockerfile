FROM ubuntu:xenial
LABEL maintainer="@singe at SensePost <research@sensepost.com>"

# Needed so we can install resolvconf in the container
RUN echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections

# Put our files in place
COPY /nssh /bin/nssh
RUN chmod +x /bin/nssh
COPY /entrypoint.sh /opt/
RUN chmod +x /opt/entrypoint.sh

# Install required tooling
RUN apt-get update -o Dir::Etc::sourcelist="sources.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" \
  && apt-get install -y bash resolvconf iproute2 psmisc iptables iputils-ping

# Define our startup
CMD /opt/entrypoint.sh && /bin/nssh
