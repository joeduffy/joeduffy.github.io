FROM ubuntu:trusty
MAINTAINER joeduffy@acm.org

RUN apt-get update -y

# Install the GitHub Pages and Jekyll requirements.
RUN apt-get install ruby-dev -y
RUN apt-get install make zlib1g-dev -y
RUN gem install github-pages

# Add our content, build it, serve it.
ADD . /site
WORKDIR /site
RUN jekyll build

EXPOSE 4000
ENTRYPOINT [ "bundle", "exec", jekyll", "serve" ]

