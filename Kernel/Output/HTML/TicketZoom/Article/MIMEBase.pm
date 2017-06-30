# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::TicketZoom::Article::MIMEBase;

use parent 'Kernel::Output::HTML::TicketZoom::Article::Base';

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsPositiveInteger);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::CommunicationChannel',
    'Kernel::System::Main',
    'Kernel::System::Log',
    'Kernel::System::Ticket::Article',
    'Kernel::Output::HTML::Article::MIMEBase',
);

=head2 ArticleRender()

Returns article html.

    my $HTML = $ArticleBaseObject->ArticleRender(
        TicketID                    => 123,         # (required)
        ArticleID                   => 123,         # (required)
        UserID                      => 123,         # (required)
        ShowBrowserLinkMessage      => 1,           # (optional) Default: 0.
        ArticleActions              => [],          # (optional)
    );

Result:
    $HTML = "<div>...</div>";

=cut

sub ArticleRender {
    my ( $Self, %Param ) = @_;

    # Check needed stuff.
    for my $Needed (qw(TicketID ArticleID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    my $ConfigObject         = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject         = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $MainObject           = $Kernel::OM->Get('Kernel::System::Main');
    my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForArticle(%Param);

    my %Article = $ArticleBackendObject->ArticleGet(
        %Param,
        RealNames => 1,
    );
    if ( !%Article ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Article not found (ArticleID=$Param{ArticleID})!"
        );
        return;
    }

    # Get channel specific fields
    my %ArticleFields = $LayoutObject->ArticleFields(%Param);

    # Get dynamic fields and accounted time
    my %ArticleMetaFields = $Self->ArticleMetaFields(%Param);

    # Get data from modules like Google CVE search
    my @ArticleModuleMeta = $Self->_ArticleModuleMeta(%Param);

    my $RichTextEnabled = $ConfigObject->Get('Ticket::Frontend::ZoomRichTextForce')
        || $LayoutObject->{BrowserRichText}
        || 0;

    # Get attachment index (excluding body attachments).
    my %AtmIndex = $ArticleBackendObject->ArticleAttachmentIndex(
        ArticleID        => $Param{ArticleID},
        UserID           => $Param{UserID},
        ExcludePlainText => 1,
        ExcludeHTMLBody  => $RichTextEnabled,
        ExcludeInline    => $RichTextEnabled,
    );

    my @ArticleAttachments;

    # Add block for attachments.
    if (%AtmIndex) {

        my $Config = $ConfigObject->Get('Ticket::Frontend::ArticleAttachmentModule');

        ATTACHMENT:
        for my $FileID ( sort keys %AtmIndex ) {

            my $Attachment;

            # Run article attachment modules.
            next ATTACHMENT if ref $Config ne 'HASH';
            my %Jobs = %{$Config};

            JOB:
            for my $Job ( sort keys %Jobs ) {
                my %File = %{ $AtmIndex{$FileID} };

                # load module
                next JOB if !$MainObject->Require( $Jobs{$Job}->{Module} );
                my $Object = $Jobs{$Job}->{Module}->new(
                    %{$Self},
                    TicketID  => $Param{TicketID},
                    ArticleID => $Param{ArticleID},
                    UserID    => $Param{UserID},
                );

                # run module
                my %Data = $Object->Run(
                    File => {
                        %File,
                        FileID => $FileID,
                    },
                    TicketID => $Param{TicketID},
                    Article  => \%Article,
                );

                if (%Data) {
                    %File = %Data;
                }

                $File{Links} = [
                    {
                        Action => $File{Action},
                        Class  => $File{Class},
                        Link   => $File{Link},
                        Target => $File{Target},
                    },
                ];
                if ( $File{Action} && $File{Action} ne 'Download' ) {
                    delete $File{Action};
                    delete $File{Class};
                    delete $File{Link};
                    delete $File{Target};
                }

                if ($Attachment) {
                    push @{ $Attachment->{Links} }, $File{Links}->[0];
                }
                else {
                    $Attachment = \%File;
                }
            }
            push @ArticleAttachments, $Attachment;
        }
    }

    # Check if HTML should be displayed.
    my $ShowHTML = $ConfigObject->Get('Ticket::Frontend::ZoomRichTextForce')
        || $LayoutObject->{BrowserRichText}
        || 0;

    # Check if HTML attachment is missing.
    if ( $ShowHTML && !$Kernel::OM->Get('Kernel::Output::HTML::Article::MIMEBase')->HTMLBodyAttachmentIDGet(%Param) ) {
        $ShowHTML = 0;
    }

    my $ArticleContent;

    if ($ShowHTML) {
        if ( $Param{ShowBrowserLinkMessage} ) {
            $LayoutObject->Block(
                Name => 'BrowserLinkMessage',
            );
        }
    }
    else {
        $ArticleContent = $LayoutObject->ArticlePreview(
            %Param,
            ResultType => 'plain',
        );

        # html quoting
        $ArticleContent = $LayoutObject->Ascii2Html(
            NewLine        => $ConfigObject->Get('DefaultViewNewLine'),
            Text           => $ArticleContent,
            VMax           => $ConfigObject->Get('DefaultViewLines') || 5000,
            HTMLResultMode => 1,
            LinkFeature    => 1,
        );
    }

    my $ChannelObject = $Kernel::OM->Get('Kernel::System::CommunicationChannel')->ChannelObjectGet(
        ChannelID => $Article{CommunicationChannelID},
    );

    my $Content = $LayoutObject->Output(
        TemplateFile => 'Article/MIMEBase',
        Data         => {
            %Article,
            ArticleFields        => \%ArticleFields,
            ArticleMetaFields    => \%ArticleMetaFields,
            ArticleModuleMeta    => \@ArticleModuleMeta,
            Attachments          => \@ArticleAttachments,
            MenuItems            => $Param{ArticleActions},
            Body                 => $ArticleContent,
            HTML                 => $ShowHTML,
            CommunicationChannel => $ArticleBackendObject->ChannelNameGet(),
            ChannelIcon          => $ChannelObject->ChannelIconGet(),
            SenderImage          => $Self->_ArticleSenderImage(
                Sender => $Article{From},
            ),
            SenderInitials => $Self->_ArticleSenderInitials(
                Sender => $Article{FromRealname},
            ),
        },
    );

    return $Content;
}

1;
