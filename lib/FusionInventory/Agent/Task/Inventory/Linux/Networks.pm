package FusionInventory::Agent::Task::Inventory::Linux::Networks;

use strict;
use warnings;

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Network;
use FusionInventory::Agent::Tools::Unix;
use FusionInventory::Agent::Tools::Linux;

sub isEnabled {
    return 1;
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    my $routes = getRoutingTable(command => 'netstat -nr', logger => $logger);
    my @interfaces = _getInterfaces(logger => $logger);

    foreach my $interface (@interfaces) {
        $interface->{IPGATEWAY} = $params{routes}->{$interface->{IPSUBNET}}
            if $interface->{IPSUBNET};

        $inventory->addEntry(
            section => 'NETWORKS',
            entry   => $interface
        );
    }

    $inventory->setHardware({
        DEFAULTGATEWAY => $routes->{'0.0.0.0'}
    });
}

sub _getInterfaces {
    my (%params) = @_;

    my $logger = $params{logger};

    my @interfaces = _getInterfacesBase(logger => $logger);

    foreach my $interface (@interfaces) {
        $interface->{IPSUBNET} = getSubnetAddress(
            $interface->{IPADDRESS},
            $interface->{IPMASK}
        );

        $interface->{IPDHCP} = getIpDhcp(
            $logger,
            $interface->{DESCRIPTION}
        );

        if (_isWifi($logger, $interface->{DESCRIPTION})) {
            $interface->{TYPE} = "wifi";
        }

        my ($driver, $pcislot) = _getUevent(
            $interface->{DESCRIPTION}
        );
        $interface->{DRIVER} = $driver if $driver;
        $interface->{PCISLOT} = $pcislot if $pcislot;

        $interface->{VIRTUALDEV} = _isVirtual(
            logger => $logger,
            name   => $interface->{DESCRIPTION},
            slot   => $interface->{PCISLOT}
        );

        $interface->{SLAVES} = _getSlaves($interface->{DESCRIPTION});
    }

    return @interfaces;
}

sub _getInterfacesBase {
    my (%params) = @_;

    my $logger = $params{logger};
    $logger->debug("retrieving interfaces list...");

    if (canRun('/sbin/ip')) {
        my @interfaces = getInterfacesFromIp(logger => $logger);
        $logger->debug_result('running /sbin/ip command', @interfaces);
        return @interfaces if @interfaces;
    } else {
        $logger->debug_absence($logger, '/sbin/ip command');
    }

    if (canRun('/sbin/ifconfig')) {
        my @interfaces = getInterfacesFromIfconfig(logger => $logger);
        $logger->debug_result('running /sbin/ifconfig command', @interfaces);
        return @interfaces if @interfaces;
    } else {
        $logger->debug_absence('/sbin/ifconfig command');
    }

    return;
}

# Handle slave devices (bonding)
sub _getSlaves {
    my ($name) = @_;

    my @slaves = ();
    while (my $slave = glob("/sys/class/net/$name/slave_*")) {
        if ($slave =~ /\/slave_(\w+)/) {
            push(@slaves, $1);
        }
    }

    return join (",", @slaves);
}

# Handle virtual devices (bridge)
sub _isVirtual {
    my (%params) = @_;

    return 0 if $params{slot};

    if (-d "/sys/devices/virtual/net/") {
        return -d "/sys/devices/virtual/net/$params{name}";
    }

    if (canRun('brctl')) {
        # Let's guess
        my %bridge;
        my $handle = getFileHandle(
            logger => $params{logger},
            command => 'brctl show'
        );
        my $line = <$handle>;
        while (my $line = <$handle>) {
            next unless $line =~ /^(\w+)\s/;
            $bridge{$1} = 1;
        }
        close $handle;

        return defined $bridge{$params{name}};
    }

    return 0;
}

sub _isWifi {
    my ($logger, $name) = @_;

    my $count = getLinesCount(
        logger  => $logger,
        command => "/sbin/iwconfig $name"
    );
    return $count > 2;
}

sub _getUevent {
    my ($name) = @_;

    my $file = "/sys/class/net/$name/device/uevent";
    my $handle = getFileHandle(file => $file);
    return unless $handle;

    my ($driver, $pcislot);
    while (my $line = <$handle>) {
        $driver = $1 if $line =~ /^DRIVER=(\S+)/;
        $pcislot = $1 if $line =~ /^PCI_SLOT_NAME=(\S+)/;
    }
    close $handle;

    return ($driver, $pcislot);
}

1;
