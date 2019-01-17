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

# Return a list of WORKERS or CONTROLLERS from environments
# See also etc/vboxdns.service.in
# Input:
#   env_name  The environment name (worker, controller)
def get_ips(env_name)
  ips = ENV[env_name.to_s.upcase].to_s.split
  ips.map do |w|
    _, w_index = w.split("-")
    w_index ? "#{ENV['IP_PREFIX']}.#{w_index}" : nil
  end.compact.shuffle
end

RubyDNS::run_server(INTERFACES) do
  # worker-<index>    returns <IP_PREFIX>.<index>
  # controlle-<index> returns <IP_PREFIX>.<index>
  match(%r{((worker)|(controller))-([0-9]+)}, IN::A) do |transaction, match_data|
    transaction.respond!("#{ENV['IP_PREFIX']}.#{match_data[4]}", resource_class: IN::A, ttl: 10)
  end

  # k8s   return all workers IPs
  match(%r{.*k8s$}, IN::A) do |transaction|
    get_ips("workers").each do |ip|
      transaction.respond!(ip, resource_class: IN::A, ttl: 10)
    end
  end

  otherwise do |transaction|
    transaction.passthrough!(UPSTREAM)
  end
end
