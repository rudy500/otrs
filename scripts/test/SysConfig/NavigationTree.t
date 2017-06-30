# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

## no critic (Modules::RequireExplicitPackage)
use strict;
use warnings;
use utf8;

use vars (qw($Self));

use Kernel::Config;

# Get needed objects
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {

        # RestoreDatabase => 1,
    },
);
my $HelperObject      = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $SysConfigObject   = $Kernel::OM->Get('Kernel::System::SysConfig');
my $ConfigObject      = $Kernel::OM->Get('Kernel::Config');
my $SysConfigDBObject = $Kernel::OM->Get('Kernel::System::SysConfig::DB');

# Basic tests
my @Tests = (
    {
        Description => 'Missing Array',
        Config      => {
            'Tree' => {
                'Core' => {
                    'Core::CustomerUser' => {},
                },
            },
        },
        ExpectedResult => undef,
    },
    {
        Description => 'Missing Tree',
        Config      => {
            'Array' => [
                'Core',
                'Core::CustomerUser',
            ],
        },
        ExpectedResult => undef,
    },
    {
        Description => 'Pass #1',
        Config      => {
            'Array' => [
                'Core',
                'Core::CustomerUser',
            ],
            'Tree' => {
                'Core' => {
                    'Core::CustomerUser' => {},
                },
            },
        },
        ExpectedResult => {
            'Core' => {
                'Core::CustomerUser' => {},
            },
        },
    },
    {
        Description => 'Pass #2',
        Config      => {
            'Array' => [
                'Core',
                'Core::CustomerUser',
                'Core::CustomerUser::CustomerUserßšđč',
            ],
            'Tree' => {
                'Core' => {
                    'Core::CustomerUser' => {},
                },
            },
        },
        ExpectedResult => {
            'Core' => {
                'Core::CustomerUser' => {
                    'Core::CustomerUser::CustomerUserßšđč' => {},
                },
            },
        },
    },
    {
        Description => 'Pass #3',
        Config      => {
            'Array' => [
                'Core',
                'Core::CustomerUser',
                'Core::CustomerUser::CustomerUserßšđč',
            ],
            'Tree' => {
            },
        },
        ExpectedResult => {
            'Core' => {
                'Core::CustomerUser' => {
                    'Core::CustomerUser::CustomerUserßšđč' => {},
                },
            },
        },
    },
    {
        Description => 'Pass #4',
        Config      => {
            'Array' => [],
            'Tree'  => {
                'Core' => {
                    'Core::CustomerUser' => {},
                },
            },
        },
        ExpectedResult => {
            'Core' => {
                'Core::CustomerUser' => {},
            },
        },
    },
    {
        Description => 'Pass #5',
        Config      => {
            'Array' => [
                'Core',
                'Core::CustomerUser',
            ],
            'Tree' => {
                'Ticket' => {
                    'Ticket::States' => {},
                },
            },
        },
        ExpectedResult => {
            'Core' => {
                'Core::CustomerUser' => {}
            },
            'Ticket' => {
                'Ticket::States' => {}
                }
        },
    },
);

for my $Test (@Tests) {
    my %Result = $SysConfigObject->_NavigationTree( %{ $Test->{Config} } );

    if ( !$Test->{ExpectedResult} ) {
        $Self->True(
            !%Result,
            $Test->{Description} . ': _NavigationTree(): Result must be undef.',
            )
    }
    else {
        $Self->IsDeeply(
            \%Result,
            $Test->{ExpectedResult},
            $Test->{Description} . ': _NavigationTree(): Result must match expected one.',
        );
    }
}

1;
