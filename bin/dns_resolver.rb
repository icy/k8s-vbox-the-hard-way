#!/usr/bin/env ruby

# Author  : Ky-Anh Huynh
# License : MIT
# Purpose : Provide simple dns server for k8s cluster

require 'rubydns'

INTERFACES = [
  [:udp, "0.0.0.0", 53],
  [:tcp, "0.0.0.0", 53],
]

IN = Resolv::DNS::Resource::IN

UPSTREAM = RubyDNS::Resolver.new(
  [[:udp, "10.0.2.2", 53]]
)

RubyDNS::run_server(INTERFACES) do
  match(%r{((worker)|(controller))-([0-9]+)}, IN::A) do |transaction, match_data|
    transaction.respond!("#{ENV['IP_PREFIX']}.#{match_data[4]}")
  end

  otherwise do |transaction|
    transaction.passthrough!(UPSTREAM)
  end
end
