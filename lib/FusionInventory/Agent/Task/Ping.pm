package FusionInventory::Agent::Task::Ping;

# Keep this line, used by getVersionFromTaskModuleFile
# VERSION FROM Agent.pm
use strict;
use warnings;
use base 'FusionInventory::Agent::Task';

use FusionInventory::Agent::Network;
use FusionInventory::Agent::XML::Query::SimpleMessage;

sub main {
    my ($self) = @_;

    if (!$self->{target}->isa('FusionInventory::Agent::Target::Server')) {
        $self->{logger}->debug("No server. Exiting...");
        return;
    }

    my $options = $self->{prologresp}->getOptionsInfoByName('PING');
    return unless $options;
    my $option = shift @$options;
    return unless $option;

    $self->{logger}->debug("Ping ID:". $option->{ID});

    my $network = FusionInventory::Agent::Network->new({
        logger => $self->{logger},
        config => $self->{config},
        target => $self->{target},
    });

    my $message = FusionInventory::Agent::XML::Query::SimpleMessage->new({
        logger          => $self->{logger},
        deviceid        => $self->{target}->{deviceid},
        currentDeviceid => $self->{target}->{currentDeviceid},
        msg      => {
            QUERY => 'PING',
            ID    => $option->{ID},
        },
    });

    # is this really useful ?
    $self->{network} = $network;

    $self->{logger}->debug("Pong!");
    $network->send( { message => $message } );

}

1;
