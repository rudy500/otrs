# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentTicketArticleContent;
## nofilter(TidyAll::Plugin::OTRS::Perl::Print)

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get ArticleID
    my $TicketID  = $ParamObject->GetParam( Param => 'TicketID' );
    my $ArticleID = $ParamObject->GetParam( Param => 'ArticleID' );

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    # check params
    if ( !$ArticleID || !$TicketID ) {
        $LogObject->Log(
            Message  => 'TicketID and ArticleID are needed!',
            Priority => 'error',
        );
        return $LayoutObject->ErrorScreen();
    }

    my $TicketNumber = $Kernel::OM->Get('Kernel::System::Ticket')->TicketNumberLookup(
        TicketID => $TicketID,
    );

    my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForArticle(
        TicketID  => $TicketID,
        ArticleID => $ArticleID,
    );

    # Check permissions.
    my %Article = $ArticleBackendObject->ArticleGet(
        TicketID      => $TicketID,
        ArticleID     => $ArticleID,
        DynamicFields => 0,
        UserID        => $Self->{UserID},
    );

    my $Access = $Kernel::OM->Get('Kernel::System::Ticket')->TicketPermission(
        Type     => 'ro',
        TicketID => $TicketID,
        UserID   => $Self->{UserID},
    );
    if ( !$Access ) {
        return $LayoutObject->NoPermission( WithHeader => 'yes' );
    }

    my %Data;

    # Render article content.
    my $ArticleContent = $LayoutObject->ArticlePreview(
        TicketID  => $TicketID,
        ArticleID => $ArticleID,
    );

    my $Content = $LayoutObject->Output(
        Template => '[% Data.HTML %]',
        Data     => {
            HTML => $ArticleContent,
        },
    );

    %Data = (
        Content            => $Content,
        ContentAlternative => "",
        ContentID          => "",
        ContentType        => "text/html; charset=\"utf-8\"",
        Disposition        => "inline",
        FilesizeRaw        => bytes::length($Content),
    );

    if ( !%Data ) {
        $LogObject->Log(
            Message  => "No such attacment! May be an attack!!!",
            Priority => 'error',
        );
        return $LayoutObject->ErrorScreen();
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # set download type to inline
    $ConfigObject->Set(
        Key   => 'AttachmentDownloadType',
        Value => 'inline'
    );

    # just return for non-html attachment (e. g. images)
    if ( $Data{ContentType} !~ /text\/html/i ) {
        return $LayoutObject->Attachment(
            %Data,
            Sandbox => 1,
        );
    }

    # set filename for inline viewing
    $Data{Filename} = "Ticket-$TicketNumber-ArticleID-$Article{ArticleID}.html";

    my $LoadExternalImages = $ParamObject->GetParam(
        Param => 'LoadExternalImages'
    ) || 0;

    # safety check only on customer article
    if ( !$LoadExternalImages && $Article{SenderType} ne 'customer' ) {
        $LoadExternalImages = 1;
    }

    # generate base url
    my $URL = 'Action=AgentTicketAttachment;Subaction=HTMLView'
        . ";TicketID=$TicketID;ArticleID=$ArticleID;FileID=";

    # replace links to inline images in html content
    my %AtmBox = $ArticleBackendObject->ArticleAttachmentIndex(
        ArticleID => $ArticleID,
        UserID    => $Self->{UserID},
    );

    # reformat rich text document to have correct charset and links to
    # inline documents
    %Data = $LayoutObject->RichTextDocumentServe(
        Data               => \%Data,
        URL                => $URL,
        Attachments        => \%AtmBox,
        LoadExternalImages => $LoadExternalImages,
    );

    # Format links if FilterText is enabled.
    if ( $ConfigObject->Get('Frontend::Output::FilterText') ) {
        $Data{Content} = $LayoutObject->LinkQuote(
            Text => $Data{Content},
        );
    }

    # if there is unexpectedly pgp decrypted content in the html email (OE),
    # we will use the article body (plain text) from the database as fall back
    # see bug#9672
    if (
        $Data{Content} =~ m{
        ^ .* -----BEGIN [ ] PGP [ ] MESSAGE-----  .* $      # grep PGP begin tag
        .+                                                  # PGP parts may be nested in html
        ^ .* -----END [ ] PGP [ ] MESSAGE-----  .* $        # grep PGP end tag
    }xms
        )
    {

        # html quoting
        $Article{Body} = $LayoutObject->Ascii2Html(
            NewLine        => $ConfigObject->Get('DefaultViewNewLine'),
            Text           => $Article{Body},
            VMax           => $ConfigObject->Get('DefaultViewLines') || 5000,
            HTMLResultMode => 1,
            LinkFeature    => 1,
        );

        # use the article body as content, because pgp was definitly descrypted if possible
        $Data{Content} = $Article{Body};
    }

    # return html attachment
    return $LayoutObject->Attachment(
        %Data,
        Sandbox => 1,
    );
}

1;
