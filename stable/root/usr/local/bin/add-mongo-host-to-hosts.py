#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from urllib.parse import urlparse
from argparse import ArgumentParser
import dns.resolver
import re
import sys

def resolve_host_ip(host):
    ip = []
    try:
        ip.extend(map(str, dns.resolver.resolve(host, "A")))
    except dns.resolver.NoAnswer:
        pass
    try:
        ip.extend(map(str, dns.resolver.resolve(host, "AAAA")))
    except dns.resolver.NoAnswer:
        pass
    assert ip, f"Could not resolve IP for host: {host}"
    return ip

def resolve_mongodb_hosts(mongo_uri):
    parsed = urlparse(mongo_uri)
    scheme = parsed.scheme
    resolved_hosts = []

    if scheme == "mongodb+srv":
        hostname = parsed.hostname
        srv_records = dns.resolver.resolve(f"_mongodb._tcp.{hostname}", "SRV")
        for srv in srv_records:
            target = str(srv.target).rstrip('.')
            resolved_hosts.append((target, resolve_host_ip(target)))
        return resolved_hosts

    elif scheme == "mongodb":
        without_scheme = mongo_uri.split("://", 1)[1]
        if '@' in without_scheme:
            _, hosts_part = without_scheme.split('@', 1)
        else:
            hosts_part = without_scheme

        hosts_string = hosts_part.split('/')[0].split('&')[0]
        host_list = hosts_string.split(',')

        for host_entry in host_list:
            host = host_entry.split(':')[0]
            resolved_hosts.append((host, resolve_host_ip(host)))
        return resolved_hosts
    print(f"Unsupported URI scheme: {scheme}", file=sys.stderr)
    sys.exit(1)

def get_modified_hosts_file(mongo_uri, hosts_file):
    with open(hosts_file, 'r') as f:
        hosts = [line.strip() for line in f if line.strip()]
    resolved_host = resolve_mongodb_hosts(mongo_uri)
    patterns = list(map(re.compile, [r"\s+{}".format(re.escape(hostname)) for hostname, _ in resolved_host]))
    filtered_lines = [
        line for line in hosts
        if not any(pattern.search(line) for pattern in patterns)
    ]
    for hostname, ips in resolved_host:
        for ip in ips:
            filtered_lines.append(f"{ip} {hostname}")
    return '\n'.join(filtered_lines)

def main():
    parser = ArgumentParser(description="Update hosts file with resolved MongoDB hosts")
    parser.add_argument("-u", "--uri", required=True, help="MongoDB URI")
    parser.add_argument("-f", "--file", default="/etc/hosts", help="Path to hosts file")
    args = parser.parse_args()
    modified_hosts = get_modified_hosts_file(args.uri, args.file)
    with open(args.file, 'w') as f:
        f.write(modified_hosts + '\n')

if __name__ == "__main__":
    main()
