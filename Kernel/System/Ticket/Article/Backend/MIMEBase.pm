# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::Article::Backend::MIMEBase;

use strict;
use warnings;

use parent 'Kernel::System::Ticket::Article::Backend::Base';

use Kernel::System::EmailParser;
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::CustomerUser',
    'Kernel::System::DB',
    'Kernel::System::Email',
    'Kernel::System::HTMLUtils',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::PostMaster::LoopProtection',
    'Kernel::System::State',
    'Kernel::System::TemplateGenerator',
    'Kernel::System::Ticket',
    'Kernel::System::Ticket::Article',
    'Kernel::System::User',
);

=head1 NAME

Kernel::System::Ticket::Article::Backend::MIMEBase - base class for all C<MIME> based article backends

=head1 DESCRIPTION

This is a base class for article data in C<MIME> format and should not be instantiated directly.
Always get real backend instead, i.e. C<Email>, C<Phone> or C<Internal>.

Basic article data is always stored in a database table, but extended data uses configured article
storage backend. For plain text representation of the message, use C<Body> field. For original
message with email headers, use L</ArticlePlain()> method to retrieve it from storage backend.
Attachments are handled by the storage backends, and can be retrieved via L</ArticleAttachment()>.

Inherits from L<Kernel::System::Ticket::Article::Backend::Base>.

See also L<Kernel::System::Ticket::Article::Backend::MIMEBase::Base> and
L<Kernel::System::Ticket::Article::Backend::Email>.

=head1 PUBLIC INTERFACE

=head2 new()

Don't instantiate this class directly, get instances of the real backends instead:

    my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Article)->BackendForChannel(ChannelName => 'Email');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # Call constructor of the base class.
    my $Self = $Type->SUPER::new(%Param);

    # 0=off; 1=on;
    $Self->{Debug} = $Param{Debug} || 0;

    # Persistent for this object's lifetime so that we can have article objects with different storage modules.
    $Self->{ArticleStorageModule} = $Param{ArticleStorageModule}
        || $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Article::Backend::MIMEBase')->{'ArticleStorage'}
        || 'Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageDB';

    return $Self;
}

=head2 ArticleCreate()

Create a MIME article.

    my $ArticleID = $ArticleBackendObject->ArticleCreate(
        TicketID             => 123,                              # (required)
        SenderTypeID         => 1,                                # (required)
                                                                  # or
        SenderType           => 'agent',                          # (required) agent|system|customer
        IsVisibleForCustomer => 1,                                # (required) Is article visible for customer?
        UserID               => 123,                              # (required)

        From           => 'Some Agent <email@example.com>',       # not required but useful
        To             => 'Some Customer A <customer-a@example.com>', # not required but useful
        Cc             => 'Some Customer B <customer-b@example.com>', # not required but useful
        ReplyTo        => 'Some Customer B <customer-b@example.com>', # not required
        Subject        => 'some short description',               # not required but useful
        Body           => 'the message text',                     # not required but useful
        MessageID      => '<asdasdasd.123@example.com>',          # not required but useful
        InReplyTo      => '<asdasdasd.12@example.com>',           # not required but useful
        References     => '<asdasdasd.1@example.com> <asdasdasd.12@example.com>', # not required but useful
        ContentType    => 'text/plain; charset=ISO-8859-15',      # or optional Charset & MimeType
        HistoryType    => 'OwnerUpdate',                          # EmailCustomer|Move|AddNote|PriorityUpdate|WebRequestCustomer|...
        HistoryComment => 'Some free text!',
        Attachment => [
            {
                Content     => $Content,
                ContentType => $ContentType,
                Filename    => 'lala.txt',
            },
            {
                Content     => $Content,
                ContentType => $ContentType,
                Filename    => 'lala1.txt',
            },
        ],
        NoAgentNotify    => 0,                                      # if you don't want to send agent notifications
        AutoResponseType => 'auto reply'                            # auto reject|auto follow up|auto reply/new ticket|auto remove

        ForceNotificationToUserID   => [ 1, 43, 56 ],               # if you want to force somebody
        ExcludeNotificationToUserID => [ 43,56 ],                   # if you want full exclude somebody from notfications,
                                                                    # will also be removed in To: line of article,
                                                                    # higher prio as ForceNotificationToUserID
        ExcludeMuteNotificationToUserID => [ 43,56 ],               # the same as ExcludeNotificationToUserID but only the
                                                                    # sending gets muted, agent will still shown in To:
                                                                    # line of article
    );

Example with "Charset & MimeType" and no "ContentType".

    my $ArticleID = $ArticleObject->ArticleCreate(
        TicketID             => 123,                                 # (required)
        SenderType           => 'agent',                             # (required) agent|system|customer
        IsVisibleForCustomer => 1,                                   # (required) Is article visible for customer?

        From             => 'Some Agent <email@example.com>',       # not required but useful
        To               => 'Some Customer A <customer-a@example.com>', # not required but useful
        Subject          => 'some short description',               # required
        Body             => 'the message text',                     # required
        Charset          => 'ISO-8859-15',
        MimeType         => 'text/plain',
        HistoryType      => 'OwnerUpdate',                          # EmailCustomer|Move|AddNote|PriorityUpdate|WebRequestCustomer|...
        HistoryComment   => 'Some free text!',
        UserID           => 123,
        UnlockOnAway     => 1,                                      # Unlock ticket if owner is away
    );

Events:
    ArticleCreate

=cut

sub ArticleCreate {
    my ( $Self, %Param ) = @_;

    my $IncomingTime = $Kernel::OM->Create('Kernel::System::DateTime')->ToEpoch();

    my $ArticleContentPath = $Kernel::OM->Get( $Self->{ArticleStorageModule} )->BuildArticleContentPath();

    # create ArticleContentPath
    if ( !$ArticleContentPath ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ArticleContentPath!'
        );
        return;
    }

    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    # Lookup if no ID is passed.
    if ( $Param{SenderType} && !$Param{SenderTypeID} ) {
        $Param{SenderTypeID} = $ArticleObject->ArticleSenderTypeLookup( SenderType => $Param{SenderType} );
    }

    # check needed stuff
    for my $Needed (qw(TicketID UserID SenderTypeID HistoryType HistoryComment)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    if ( !defined $Param{IsVisibleForCustomer} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need IsVisibleForCustomer!"
        );
        return;
    }

    # check ContentType vs. Charset & MimeType
    if ( !$Param{ContentType} ) {
        for (qw(Charset MimeType)) {
            if ( !$Param{$_} ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Need $_!"
                );
                return;
            }
        }
        $Param{ContentType} = "$Param{MimeType}; charset=$Param{Charset}";
    }
    else {
        for (qw(ContentType)) {
            if ( !$Param{$_} ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Need $_!"
                );
                return;
            }
        }
        $Param{Charset} = '';
        if ( $Param{ContentType} =~ /charset=/i ) {
            $Param{Charset} = $Param{ContentType};
            $Param{Charset} =~ s/.+?charset=("|'|)(\w+)/$2/gi;
            $Param{Charset} =~ s/"|'//g;
            $Param{Charset} =~ s/(.+?);.*/$1/g;

        }
        $Param{MimeType} = '';
        if ( $Param{ContentType} =~ /^(\w+\/\w+)/i ) {
            $Param{MimeType} = $1;
            $Param{MimeType} =~ s/"|'//g;
        }
    }

    # for the event handler, before any actions have taken place
    my %OldTicketData = $Kernel::OM->Get('Kernel::System::Ticket')->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 1,
    );

    # get html utils object
    my $HTMLUtilsObject = $Kernel::OM->Get('Kernel::System::HTMLUtils');

    # add 'no body' if there is no body there!
    my @AttachmentConvert;
    if ( !defined $Param{Body} ) {    # allow '0' as body
        $Param{Body} = '';
    }

    # process html article
    elsif ( $Param{MimeType} =~ /text\/html/i ) {

        # add html article as attachment
        my $Attach = {
            Content     => $Param{Body},
            ContentType => "text/html; charset=\"$Param{Charset}\"",
            Filename    => 'file-2',
        };
        push @AttachmentConvert, $Attach;

        # get ASCII body
        $Param{MimeType} = 'text/plain';
        $Param{ContentType} =~ s/html/plain/i;
        $Param{Body} = $HTMLUtilsObject->ToAscii(
            String => $Param{Body},
        );
    }
    elsif ( $Param{MimeType} && $Param{MimeType} eq "application/json" ) {

        # Keep JSON body unchanged
    }

    # if body isn't text, attach body as attachment (mostly done by OE) :-/
    elsif ( $Param{MimeType} && $Param{MimeType} !~ /\btext\b/i ) {

        # add non text as attachment
        my $FileName = 'unknown';
        if ( $Param{ContentType} =~ /name="(.+?)"/i ) {
            $FileName = $1;
        }
        my $Attach = {
            Content     => $Param{Body},
            ContentType => $Param{ContentType},
            Filename    => $FileName,
        };
        push @{ $Param{Attachment} }, $Attach;

        # set ASCII body
        $Param{MimeType}    = 'text/plain';
        $Param{ContentType} = 'text/plain';
        $Param{Body}        = '- no text message => see attachment -';
    }

    # fix some bad stuff from some browsers (Opera)!
    else {
        $Param{Body} =~ s/(\n\r|\r\r\n|\r\n)/\n/g;
    }

    # strip not wanted stuff
    for my $Attribute (qw(From To Cc Subject MessageID InReplyTo References ReplyTo)) {
        if ( defined $Param{$Attribute} ) {
            $Param{$Attribute} =~ s/\n|\r//g;
        }
        else {
            $Param{$Attribute} = '';
        }
    }
    ATTRIBUTE:
    for my $Attribute (qw(MessageID)) {
        next ATTRIBUTE if !$Param{$Attribute};
        $Param{$Attribute} = substr( $Param{$Attribute}, 0, 3800 );
    }

    # Check if this is the first article (for notifications).
    my @Articles = $ArticleObject->ArticleList( TicketID => $Param{TicketID} );
    my $FirstArticle = scalar @Articles ? 0 : 1;

    # calculate MD5 of Message ID
    if ( $Param{MessageID} ) {
        $Param{MD5} = $Kernel::OM->Get('Kernel::System::Main')->MD5sum( String => $Param{MessageID} );
    }

    # Generate unique fingerprint for searching created article in database to prevent race conditions
    #   (see https://bugs.otrs.org/show_bug.cgi?id=12438).
    my $RandomString = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString(
        Length => 32,
    );
    my $ArticleInsertFingerprint = $$ . '-' . $RandomString . '-' . ( $Param{MessageID} // '' );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # Create meta article.
    my $ArticleID = $Self->_MetaArticleCreate(
        TicketID               => $Param{TicketID},
        SenderTypeID           => $Param{SenderTypeID},
        IsVisibleForCustomer   => $Param{IsVisibleForCustomer},
        CommunicationChannelID => $Self->ChannelIDGet(),
        UserID                 => $Param{UserID},
    );
    if ( !$ArticleID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Can't create meta article (TicketID=$Param{TicketID})!",
        );
        return;
    }

    return if !$DBObject->Do(
        SQL => '
            INSERT INTO article_data_mime (
                article_id, a_from, a_reply_to, a_to, a_cc, a_subject, a_message_id,
                a_message_id_md5, a_in_reply_to, a_references, a_content_type, a_body,
                incoming_time, content_path, create_time, create_by, change_time, change_by)
            VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?
            )
        ',
        Bind => [
            \$ArticleID, \$Param{From}, \$Param{ReplyTo}, \$Param{To}, \$Param{Cc},
            \$Param{Subject},
            \$ArticleInsertFingerprint,    # just for next search; will be updated with correct MessageID
            \$Param{MD5}, \$Param{InReplyTo}, \$Param{References}, \$Param{ContentType},
            \$Param{Body}, \$IncomingTime, \$ArticleContentPath, \$Param{UserID}, \$Param{UserID},
        ],
    );

    # Get article data ID.
    return if !$DBObject->Prepare(
        SQL => '
            SELECT id FROM article_data_mime
            WHERE article_id = ?
                AND a_message_id = ?
                AND incoming_time = ?
            ORDER BY id DESC
        ',
        Bind  => [ \$ArticleID, \$ArticleInsertFingerprint, \$IncomingTime, ],
        Limit => 1,
    );

    my $ArticleDataID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $ArticleDataID = $Row[0];
    }

    # Return if article data record was not created.
    if ( !$ArticleDataID ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message =>
                "Can't store article data (TicketID=$Param{TicketID}, ArticleID=$ArticleID, MessageID=$Param{MessageID})!",
        );
        return;
    }

    # Save correct Message-ID now.
    return if !$DBObject->Do(
        SQL  => 'UPDATE article_data_mime SET a_message_id = ? WHERE id = ?',
        Bind => [ \$Param{MessageID}, \$ArticleDataID, ],
    );

    # check for base64 encoded images in html body and upload them
    for my $Attachment (@AttachmentConvert) {

        if (
            $Attachment->{ContentType} eq "text/html; charset=\"$Param{Charset}\""
            && $Attachment->{Filename} eq 'file-2'
            )
        {
            $HTMLUtilsObject->EmbeddedImagesExtract(
                DocumentRef    => \$Attachment->{Content},
                AttachmentsRef => \@AttachmentConvert,
            );
        }
    }

    # add converted attachments
    for my $Attachment (@AttachmentConvert) {
        $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleWriteAttachment(
            %{$Attachment},
            ArticleID => $ArticleID,
            UserID    => $Param{UserID},
        );
    }

    # add attachments
    if ( $Param{Attachment} ) {
        for my $Attachment ( @{ $Param{Attachment} } ) {
            $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleWriteAttachment(
                %{$Attachment},
                ArticleID => $ArticleID,
                UserID    => $Param{UserID},
            );
        }
    }

    $ArticleObject->_ArticleCacheClear(
        TicketID => $Param{TicketID},
    );

    # add history row
    $Kernel::OM->Get('Kernel::System::Ticket')->HistoryAdd(
        ArticleID    => $ArticleID,
        TicketID     => $Param{TicketID},
        CreateUserID => $Param{UserID},
        HistoryType  => $Param{HistoryType},
        Name         => $Param{HistoryComment},
    );

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');

    # unlock ticket if the owner is away (and the feature is enabled)
    if (
        $Param{UnlockOnAway}
        && $OldTicketData{Lock} eq 'lock'
        && $ConfigObject->Get('Ticket::UnlockOnAway')
        )
    {
        my %OwnerInfo = $UserObject->GetUserData(
            UserID => $OldTicketData{OwnerID},
        );

        if ( $OwnerInfo{OutOfOfficeMessage} ) {
            $Kernel::OM->Get('Kernel::System::Ticket')->TicketLockSet(
                TicketID => $Param{TicketID},
                Lock     => 'unlock',
                UserID   => $Param{UserID},
            );
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message =>
                    "Ticket [$OldTicketData{TicketNumber}] unlocked, current owner is out of office!",
            );
        }
    }

    # event
    $Self->EventHandler(
        Event => 'ArticleCreate',
        Data  => {
            ArticleID     => $ArticleID,
            TicketID      => $Param{TicketID},
            OldTicketData => \%OldTicketData,
        },
        UserID => $Param{UserID},
    );

    # reset unlock if needed
    if ( !$Param{SenderType} ) {
        $Param{SenderType} = $ArticleObject->ArticleSenderTypeLookup( SenderTypeID => $Param{SenderTypeID} );
    }

    # reset unlock time if customer sent an update
    if ( $Param{SenderType} eq 'customer' ) {

        # Check if previous sender was an agent.
        my $AgentSenderTypeID  = $ArticleObject->ArticleSenderTypeLookup( SenderType => 'agent' );
        my $SystemSenderTypeID = $ArticleObject->ArticleSenderTypeLookup( SenderType => 'system' );
        my @Articles           = $ArticleObject->ArticleList(
            TicketID => $Param{TicketID},
        );

        my $LastSenderTypeID;
        ARTICLE:
        for my $Article ( reverse @Articles ) {
            next ARTICLE if $Article->{ArticleID} eq $ArticleID;
            next ARTICLE if $Article->{SenderTypeID} eq $SystemSenderTypeID;
            $LastSenderTypeID = $Article->{SenderTypeID};
            last ARTICLE;
        }

        if ( $LastSenderTypeID && $LastSenderTypeID == $AgentSenderTypeID ) {
            $Kernel::OM->Get('Kernel::System::Ticket')->TicketUnlockTimeoutUpdate(
                UnlockTimeout => $IncomingTime,
                TicketID      => $Param{TicketID},
                UserID        => $Param{UserID},
            );
        }
    }

    # check if latest article is sent to customer
    elsif ( $Param{SenderType} eq 'agent' ) {
        $Kernel::OM->Get('Kernel::System::Ticket')->TicketUnlockTimeoutUpdate(
            UnlockTimeout => $IncomingTime,
            TicketID      => $Param{TicketID},
            UserID        => $Param{UserID},
        );
    }

    # send auto response
    if ( $Param{AutoResponseType} ) {
        $Self->SendAutoResponse(
            OrigHeader           => $Param{OrigHeader},
            TicketID             => $Param{TicketID},
            UserID               => $Param{UserID},
            AutoResponseType     => $Param{AutoResponseType},
            SenderTypeID         => $Param{SenderTypeID},
            IsVisibleForCustomer => $Param{IsVisibleForCustomer},
        );
    }

    # send no agent notification!?
    return $ArticleID if $Param{NoAgentNotify};

    my %Ticket = $Kernel::OM->Get('Kernel::System::Ticket')->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 0,
    );

    # remember agent to exclude notifications
    my @SkipRecipients;
    if ( $Param{ExcludeNotificationToUserID} && ref $Param{ExcludeNotificationToUserID} eq 'ARRAY' )
    {
        for my $UserID ( @{ $Param{ExcludeNotificationToUserID} } ) {
            push @SkipRecipients, $UserID;
        }
    }

    # remember agent to exclude notifications / already sent
    my %DoNotSendMute;
    if (
        $Param{ExcludeMuteNotificationToUserID}
        && ref $Param{ExcludeMuteNotificationToUserID} eq 'ARRAY'
        )
    {
        for my $UserID ( @{ $Param{ExcludeMuteNotificationToUserID} } ) {
            push @SkipRecipients, $UserID;
        }
    }

    my $ExtraRecipients;
    if ( $Param{ForceNotificationToUserID} && ref $Param{ForceNotificationToUserID} eq 'ARRAY' ) {
        $ExtraRecipients = $Param{ForceNotificationToUserID};
    }

    # send agent notification on ticket create
    if (
        $FirstArticle &&
        $Param{HistoryType}
        =~ /^(EmailAgent|EmailCustomer|PhoneCallCustomer|WebRequestCustomer|SystemRequest)$/i
        )
    {
        # trigger notification event
        $Self->EventHandler(
            Event => 'NotificationNewTicket',
            Data  => {
                TicketID              => $Param{TicketID},
                ArticleID             => $ArticleID,
                SenderTypeID          => $Param{SenderTypeID},
                IsVisibleForCustomer  => $Param{IsVisibleForCustomer},
                Queue                 => $Param{Queue},
                Recipients            => $ExtraRecipients,
                SkipRecipients        => \@SkipRecipients,
                CustomerMessageParams => {%Param},
            },
            UserID => $Param{UserID},
        );
    }

    # send agent notification on adding a note
    elsif ( $Param{HistoryType} =~ /^AddNote$/i ) {

        # trigger notification event
        $Self->EventHandler(
            Event => 'NotificationAddNote',
            Data  => {
                TicketID              => $Param{TicketID},
                ArticleID             => $ArticleID,
                SenderTypeID          => $Param{SenderTypeID},
                IsVisibleForCustomer  => $Param{IsVisibleForCustomer},
                Queue                 => $Param{Queue},
                Recipients            => $ExtraRecipients,
                SkipRecipients        => \@SkipRecipients,
                CustomerMessageParams => {},
            },
            UserID => $Param{UserID},
        );
    }

    # send agent notification on follow up
    elsif ( $Param{HistoryType} =~ /^FollowUp$/i ) {

        # trigger notification event
        $Self->EventHandler(
            Event => 'NotificationFollowUp',
            Data  => {
                TicketID              => $Param{TicketID},
                ArticleID             => $ArticleID,
                SenderTypeID          => $Param{SenderTypeID},
                IsVisibleForCustomer  => $Param{IsVisibleForCustomer},
                Queue                 => $Param{Queue},
                Recipients            => $ExtraRecipients,
                SkipRecipients        => \@SkipRecipients,
                CustomerMessageParams => {%Param},
            },
            UserID => $Param{UserID},
        );
    }

    # return ArticleID
    return $ArticleID;
}

=head2 ArticleGet()

Returns single article data.

    my %Article = $ArticleBackendObject->ArticleGet(
        TicketID       => 123,   # (required)
        ArticleID      => 123,   # (required)
        DynamicFields  => 1,     # (optional) To include the dynamic field values for this article on the return structure.
        RealNames      => 1,     # (optional) To include the From/To/Cc fields with real names.
        UserID         => 123,   # (required)
    );

Returns:

    %Article = (
        TicketID             => 123,
        ArticleID            => 123,
        From                 => 'Some Agent <email@example.com>',
        To                   => 'Some Customer A <customer-a@example.com>',
        Cc                   => 'Some Customer B <customer-b@example.com>',
        ReplyTo              => 'Some Customer B <customer-b@example.com>',
        Subject              => 'some short description',
        MessageID            => '<asdasdasd.123@example.com>',
        InReplyTo            => '<asdasdasd.12@example.com>',
        References           => '<asdasdasd.1@example.com> <asdasdasd.12@example.com>',
        ContentType          => 'text/plain; charset=ISO-8859-15',
        Body                 => 'the message text',
        SenderTypeID         => 1,
        SenderType           => 'agent',
        IsVisibleForCustomer => 1,
        IncomingTime         => 1490690026,
        CreateBy             => 1,
        CreateTime           => '2017-03-28 08:33:47',
        Charset              => 'ISO-8859-15',
        MimeType             => 'text/plain',

        # If DynamicFields => 1 was passed, you'll get an entry like this for each dynamic field:
        DynamicField_X => 'value_x',

        # If RealNames => 1 was passed, you'll get fields with contact real names too:
        FromRealname => 'Some Agent',
        ToRealname   => 'Some Customer A',
        CcRealname   => 'Some Customer B',
    );

=cut

sub ArticleGet {
    my ( $Self, %Param ) = @_;

    for (qw(TicketID ArticleID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # Get meta article.
    my %Article = $Self->_MetaArticleGet(
        ArticleID => $Param{ArticleID},
        TicketID  => $Param{TicketID},
    );
    return if !%Article;

    my %ArticleSenderTypeList = $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleSenderTypeList();

    # Email parser object might be used below for its field cleanup methods only.
    my $EmailParser;
    if ( $Param{RealNames} ) {
        $EmailParser = Kernel::System::EmailParser->new(
            Mode => 'Standalone',
        );
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $SQL = '
        SELECT sadm.a_from, sadm.a_reply_to, sadm.a_to, sadm.a_cc, sadm.a_subject,
            sadm.a_message_id, sadm.a_in_reply_to, sadm.a_references, sadm.a_content_type,
            sadm.a_body, sadm.incoming_time
        FROM article_data_mime sadm
        WHERE sadm.article_id = ?
    ';
    my @Bind = ( \$Param{ArticleID} );

    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Bind  => \@Bind,
        Limit => 1,
    );

    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        %Data = (
            %Article,
            From         => $Row[0],
            ReplyTo      => $Row[1],
            To           => $Row[2],
            Cc           => $Row[3],
            Subject      => $Row[4],
            MessageID    => $Row[5],
            InReplyTo    => $Row[6],
            References   => $Row[7],
            ContentType  => $Row[8],
            Body         => $Row[9],
            IncomingTime => $Row[10],
            SenderType   => $ArticleSenderTypeList{ $Article{SenderTypeID} },
        );

        # Determine charset.
        if ( $Data{ContentType} && $Data{ContentType} =~ /charset=/i ) {
            $Data{Charset} = $Data{ContentType};
            $Data{Charset} =~ s/.+?charset=("|'|)(\w+)/$2/gi;
            $Data{Charset} =~ s/"|'//g;
            $Data{Charset} =~ s/(.+?);.*/$1/g;
        }
        else {
            $Data{Charset} = '';
        }
        $Data{ContentCharset} = $Data{Charset};    # compatibility

        # Determine MIME type.
        if ( $Data{ContentType} && $Data{ContentType} =~ /^(\w+\/\w+)/i ) {
            $Data{MimeType} = $1;
            $Data{MimeType} =~ s/"|'//g;
        }
        else {
            $Data{MimeType} = '';
        }

        RECIPIENT:
        for my $Key (qw(From To Cc Subject)) {
            next RECIPIENT if !$Data{$Key};

            # Strip unwanted stuff from some fields.
            $Data{$Key} =~ s/\n|\r//g;

            # Skip further processing for subject field.
            next RECIPIENT if $Key eq 'Subject';

            if ( $Param{RealNames} ) {

                # Check if it's a queue.
                if ( $Data{$Key} !~ /@/ ) {
                    $Data{ $Key . 'Realname' } = $Data{$Key};
                    next RECIPIENT;
                }

                # Strip out real names.
                my $Realname = '';
                EMAILADDRESS:
                for my $EmailSplit ( $EmailParser->SplitAddressLine( Line => $Data{$Key} ) ) {
                    my $Name = $EmailParser->GetRealname( Email => $EmailSplit );
                    if ( !$Name ) {
                        $Name = $EmailParser->GetEmailAddress( Email => $EmailSplit );
                    }
                    next EMAILADDRESS if !$Name;
                    if ($Realname) {
                        $Realname .= ', ';
                    }
                    $Realname .= $Name;
                }

                # Add real name lines.
                $Data{ $Key . 'Realname' } = $Realname;
            }
        }
    }

    # Check if we also need to return dynamic field data.
    if ( $Param{DynamicFields} ) {
        my %DataWithDynamicFields = $Self->_MetaArticleDynamicFieldsGet(
            Data => \%Data,
        );
        %Data = %DataWithDynamicFields;
    }

    # Return if content is empty.
    if ( !%Data ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No such article (TicketID=$Param{TicketID}, ArticleID=$Param{ArticleID})!",
        );
        return;
    }

    return %Data;
}

=head2 ArticleUpdate()

Update article data.

Note: Keys C<Body>, C<Subject>, C<From>, C<To>, C<Cc>, C<ReplyTo>, C<SenderType>, C<SenderTypeID>
and C<IsVisibleForCustomer> are implemented.

    my $Success = $ArticleBackendObject->ArticleUpdate(
        TicketID  => 123,
        ArticleID => 123,
        Key       => 'Body',
        Value     => 'New Body',
        UserID    => 123,
    );

    my $Success = $ArticleBackendObject->ArticleUpdate(
        TicketID  => 123,
        ArticleID => 123,
        Key       => 'SenderType',
        Value     => 'agent',
        UserID    => 123,
    );

Events:
    ArticleUpdate

=cut

sub ArticleUpdate {
    my ( $Self, %Param ) = @_;

    for (qw(TicketID ArticleID UserID Key)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    if ( !defined $Param{Value} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need Value!',
        );
        return;
    }

    # Lookup for sender type ID.
    if ( $Param{Key} eq 'SenderType' ) {
        $Param{Key}   = 'SenderTypeID';
        $Param{Value} = $Kernel::OM->Get('Kernel::System::Ticket::Article')->ArticleSenderTypeLookup(
            SenderType => $Param{Value},
        );
    }

    my %Map = (
        Body    => 'a_body',
        Subject => 'a_subject',
        From    => 'a_from',
        To      => 'a_to',
        Cc      => 'a_cc',
        ReplyTo => 'a_reply_to',
    );

    if ( $Map{ $Param{Key} } ) {
        return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL => "
                UPDATE article_data_mime
                SET $Map{ $Param{Key} } = ?, change_time = current_timestamp, change_by = ?
                WHERE article_id = ?
            ",
            Bind => [ \$Param{Value}, \$Param{UserID}, \$Param{ArticleID} ],
        );
    }
    else {
        return if !$Self->_MetaArticleUpdate(
            %Param,
        );
    }

    $Kernel::OM->Get('Kernel::System::Ticket::Article')->_ArticleCacheClear(
        TicketID => $Param{TicketID},
    );

    $Self->EventHandler(
        Event => 'ArticleUpdate',
        Data  => {
            TicketID  => $Param{TicketID},
            ArticleID => $Param{ArticleID},
        },
        UserID => $Param{UserID},
    );

    return 1;
}

=head2 SendAutoResponse()

Send an auto response to a customer via email.

    my $ArticleID = $ArticleBackendObject->SendAutoResponse(
        TicketID         => 123,
        AutoResponseType => 'auto reply',
        OrigHeader       => {
            From    => 'some@example.com',
            Subject => 'For the message!',
        },
        UserID => 123,
    );

Events:
    ArticleAutoResponse

=cut

sub SendAutoResponse {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(TicketID UserID OrigHeader AutoResponseType)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    # return if no notification is active
    return 1 if $Self->{SendNoNotification};

    # get orig email header
    my %OrigHeader = %{ $Param{OrigHeader} };

    # get ticket
    my %Ticket = $Kernel::OM->Get('Kernel::System::Ticket')->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 0,                  # not needed here, TemplateGenerator will fetch the ticket on its own
    );

    # get auto default responses
    my %AutoResponse = $Kernel::OM->Get('Kernel::System::TemplateGenerator')->AutoResponse(
        TicketID         => $Param{TicketID},
        AutoResponseType => $Param{AutoResponseType},
        OrigHeader       => $Param{OrigHeader},
        UserID           => $Param{UserID},
    );

    # return if no valid auto response exists
    return if !$AutoResponse{Text};
    return if !$AutoResponse{SenderRealname};
    return if !$AutoResponse{SenderAddress};

    # send if notification should be sent (not for closed tickets)!?
    my %State = $Kernel::OM->Get('Kernel::System::State')->StateGet( ID => $Ticket{StateID} );
    if (
        $Param{AutoResponseType} eq 'auto reply'
        && ( $State{TypeName} eq 'closed' || $State{TypeName} eq 'removed' )
        )
    {

        # add history row
        $Kernel::OM->Get('Kernel::System::Ticket')->HistoryAdd(
            TicketID    => $Param{TicketID},
            HistoryType => 'Misc',
            Name        => "Sent no auto response or agent notification because ticket is "
                . "state-type '$State{TypeName}'!",
            CreateUserID => $Param{UserID},
        );

        # return
        return;
    }

    # log that no auto response was sent!
    if ( $OrigHeader{'X-OTRS-Loop'} && $OrigHeader{'X-OTRS-Loop'} !~ /^(false|no)$/i ) {

        # add history row
        $Kernel::OM->Get('Kernel::System::Ticket')->HistoryAdd(
            TicketID    => $Param{TicketID},
            HistoryType => 'Misc',
            Name        => "Sent no auto-response because the sender doesn't want "
                . "an auto-response (e. g. loop or precedence header)",
            CreateUserID => $Param{UserID},
        );
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'info',
            Message  => "Sent no '$Param{AutoResponseType}' for Ticket ["
                . "$Ticket{TicketNumber}] ($OrigHeader{From}) because the "
                . "sender doesn't want an auto-response (e. g. loop or precedence header)"
        );
        return;
    }

    # check reply to for auto response recipient
    if ( $OrigHeader{ReplyTo} ) {
        $OrigHeader{From} = $OrigHeader{ReplyTo};
    }

    # get loop protection object
    my $LoopProtectionObject = $Kernel::OM->Get('Kernel::System::PostMaster::LoopProtection');

    # create email parser object
    my $EmailParser = Kernel::System::EmailParser->new(
        Mode => 'Standalone',
    );

    my @AutoReplyAddresses;
    my @Addresses = $EmailParser->SplitAddressLine( Line => $OrigHeader{From} );
    ADDRESS:
    for my $Address (@Addresses) {
        my $Email = $EmailParser->GetEmailAddress( Email => $Address );
        if ( !$Email ) {

            # add it to ticket history
            $Kernel::OM->Get('Kernel::System::Ticket')->HistoryAdd(
                TicketID     => $Param{TicketID},
                CreateUserID => $Param{UserID},
                HistoryType  => 'Misc',
                Name         => "Sent no auto response to '$Address' - no valid email address.",
            );

            # log
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Sent no auto response to '$Address' because of invalid address.",
            );
            next ADDRESS;

        }
        if ( !$LoopProtectionObject->Check( To => $Email ) ) {

            # add history row
            $Kernel::OM->Get('Kernel::System::Ticket')->HistoryAdd(
                TicketID     => $Param{TicketID},
                HistoryType  => 'LoopProtection',
                Name         => "\%\%$Email",
                CreateUserID => $Param{UserID},
            );

            # log
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "Sent no '$Param{AutoResponseType}' for Ticket ["
                    . "$Ticket{TicketNumber}] ($Email) because of loop protection."
            );
            next ADDRESS;
        }
        else {

            # increase loop count
            return if !$LoopProtectionObject->SendEmail( To => $Email );
        }

        # check if sender is e. g. MAILER-DAEMON or Postmaster
        my $NoAutoRegExp = $Kernel::OM->Get('Kernel::Config')->Get('SendNoAutoResponseRegExp');
        if ( $Email =~ /$NoAutoRegExp/i ) {

            # add it to ticket history
            $Kernel::OM->Get('Kernel::System::Ticket')->HistoryAdd(
                TicketID     => $Param{TicketID},
                CreateUserID => $Param{UserID},
                HistoryType  => 'Misc',
                Name         => "Sent no auto response to '$Email', SendNoAutoResponseRegExp matched.",
            );

            # log
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'info',
                Message  => "Sent no auto response to '$Email' because config"
                    . " option SendNoAutoResponseRegExp (/$NoAutoRegExp/i) matched.",
            );
            next ADDRESS;
        }

        push @AutoReplyAddresses, $Address;
    }

    my $AutoReplyAddresses = join( ', ', @AutoReplyAddresses );
    my $Cc;

    # also send CC to customer user if customer user id is used and addresses do not match
    if ( $Ticket{CustomerUserID} ) {

        my %CustomerUser = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
            User => $Ticket{CustomerUserID},
        );

        if (
            $CustomerUser{UserEmail}
            && $OrigHeader{From} !~ /\Q$CustomerUser{UserEmail}\E/i
            && $Param{IsVisibleForCustomer}
            )
        {
            $Cc = $CustomerUser{UserEmail};
        }
    }

    # get history type
    my $HistoryType;
    if ( $Param{AutoResponseType} =~ /^auto follow up$/i ) {
        $HistoryType = 'SendAutoFollowUp';
    }
    elsif ( $Param{AutoResponseType} =~ /^auto reply$/i ) {
        $HistoryType = 'SendAutoReply';
    }
    elsif ( $Param{AutoResponseType} =~ /^auto reply\/new ticket$/i ) {
        $HistoryType = 'SendAutoReply';
    }
    elsif ( $Param{AutoResponseType} =~ /^auto reject$/i ) {
        $HistoryType = 'SendAutoReject';
    }
    else {
        $HistoryType = 'Misc';
    }

    if ( !@AutoReplyAddresses && !$Cc ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'info',
            Message  => "No auto response addresses for Ticket [$Ticket{TicketNumber}]"
                . " (TicketID=$Param{TicketID})."
        );
        return;
    }

    # send email
    my $ArticleID = $Self->ArticleSend(
        IsVisibleForCustomer => 1,
        SenderType           => 'system',
        TicketID             => $Param{TicketID},
        HistoryType          => $HistoryType,
        HistoryComment       => "\%\%$AutoReplyAddresses",
        From                 => "$AutoResponse{SenderRealname} <$AutoResponse{SenderAddress}>",
        To                   => $AutoReplyAddresses,
        Cc                   => $Cc,
        Charset              => 'utf-8',
        MimeType             => $AutoResponse{ContentType},
        Subject              => $AutoResponse{Subject},
        Body                 => $AutoResponse{Text},
        InReplyTo            => $OrigHeader{'Message-ID'},
        Loop                 => 1,
        UserID               => $Param{UserID},
    );

    # log
    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'info',
        Message  => "Sent auto response ($HistoryType) for Ticket [$Ticket{TicketNumber}]"
            . " (TicketID=$Param{TicketID}, ArticleID=$ArticleID) to '$AutoReplyAddresses'."
    );

    # event
    $Self->EventHandler(
        Event => 'ArticleAutoResponse',
        Data  => {
            TicketID => $Param{TicketID},
        },
        UserID => $Param{UserID},
    );

    return 1;
}

=head2 ArticleDelete()

Delete article data, its plain message, and all attachments.

    my $Success = $ArticleBackendObject->ArticleDelete(
        TicketID  => 123,
        ArticleID => 123,
        UserID    => 123,
    );

=cut

sub ArticleDelete {    ## no critic;
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(ArticleID TicketID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # Delete from article storage.
    return if !$Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleDelete(%Param);

    # Delete article data.
    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM article_data_mime WHERE article_id = ?',
        Bind => [ \$Param{ArticleID} ],
    );

    # Delete meta article and associated data, and clear cache.
    return $Self->_MetaArticleDelete(
        %Param,
    );
}

=head1 STORAGE BACKEND DELEGATE METHODS

=head2 ArticleWritePlain()

Write a plain email to storage. This is a delegate method from active backend.

    my $Success = $ArticleBackendObject->ArticleWritePlain(
        ArticleID => 123,
        Email     => $EmailAsString,
        UserID    => 123,
    );

=cut

sub ArticleWritePlain {    ## no critic;
    my $Self = shift;
    return $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleWritePlain(@_);
}

=head2 ArticlePlain()

Get plain article/email from storage. This is a delegate method from active backend.

    my $PlainMessage = $ArticleBackendObject->ArticlePlain(
        ArticleID => 123,
        UserID    => 123,
    );

Returns:

    $PlainMessage = '
        From: OTRS Feedback <marketing@otrs.com>
        To: Your OTRS System <otrs@localhost>
        Subject: Welcome to OTRS!
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 8bit

        Welcome to OTRS!
        ...
    ';

=cut

sub ArticlePlain {    ## no critic;
    my $Self = shift;
    return $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticlePlain(@_);
}

=head2 ArticleDeletePlain()

Delete a plain article from storage. This is a delegate method from active backend.

    my $Success = $ArticleBackendObject->ArticleDeletePlain(
        ArticleID => 123,
        UserID    => 123,
    );

=cut

sub ArticleDeletePlain {    ## no critic;
    my $Self = shift;
    return $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleDeletePlain(@_);
}

=head2 ArticleWriteAttachment()

Write an article attachment to storage. This is a delegate method from active backend.

    my $Success = $ArticleBackendObject->ArticleWriteAttachment(
        Content            => $ContentAsString,
        ContentType        => 'text/html; charset="iso-8859-15"',
        Filename           => 'lala.html',
        ContentID          => 'cid-1234',   # optional
        ContentAlternative => 0,            # optional, alternative content to shown as body
        Disposition        => 'attachment', # or 'inline'
        ArticleID          => 123,
        UserID             => 123,
    );

=cut

sub ArticleWriteAttachment {    ## no critic;
    my $Self = shift;
    return $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleWriteAttachment(@_);
}

=head2 ArticleAttachment()

Get article attachment from storage. This is a delegate method from active backend.

    my %Attachment = $ArticleBackendObject->ArticleAttachment(
        ArticleID => 123,
        FileID    => 1,   # as returned by ArticleAttachmentIndex
        UserID    => 123,
    );

Returns:

    %Attachment = (
        Content            => 'xxxx',     # actual attachment contents
        ContentAlternative => '',
        ContentID          => '',
        ContentType        => 'application/pdf',
        Filename           => 'StdAttachment-Test1.pdf',
        FilesizeRaw        => 4722,
        Disposition        => 'attachment',
    );

=cut

sub ArticleAttachment {    ## no critic;
    my $Self = shift;
    return $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleAttachment(@_);
}

=head2 ArticleDeleteAttachment()

Delete all attachments of an article from storage. This is a delegate method from active backend.

    my $Success = $ArticleBackendObject->ArticleDeleteAttachment(
        ArticleID => 123,
        UserID    => 123,
    );

=cut

sub ArticleDeleteAttachment {    ## no critic;
    my $Self = shift;
    return $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleDeleteAttachment(@_);
}

=head2 ArticleAttachmentIndex()

Get article attachment index as hash.

    my %Index = $BackendObject->ArticleAttachmentIndex(
        ArticleID        => 123,
        UserID           => 123,
        ExcludePlainText => 1,       # (optional) Exclude plain text attachment
        ExcludeHTMLBody  => 1,       # (optional) Exclude HTML body attachment
        ExcludeInline    => 1,       # (optional) Exclude inline attachments
    );

Returns:

    my %Index = {
        '1' => {                                                # Attachment ID
            ContentAlternative => '',                           # (optional)
            ContentID          => '',                           # (optional)
            Filesize           => '4.6 KB',
            ContentType        => 'application/pdf',
            FilesizeRaw        => 4722,
            Disposition        => 'attachment',
        },
        '2' => {
            ContentAlternative => '',
            ContentID          => '',
            Filesize           => '183 B',
            ContentType        => 'text/html; charset="utf-8"',
            FilesizeRaw        => 183,
            Disposition        => 'attachment',
        },
        ...
    };

=cut

sub ArticleAttachmentIndex {
    my $Self = shift;
    return $Kernel::OM->Get( $Self->{ArticleStorageModule} )->ArticleAttachmentIndex(@_);
}

=head2 BackendSearchableFieldsGet()

Get the definition of the searchable fields as a hash.

    my %SearchableFields = $BackendObject->BackendSearchableFieldsGet();

Returns:

    my %SearchableFields = (
        'MIMEBase_From' => {
            Label      => 'From',
            Key        => 'MIMEBase_From',
            Type       => 'Text',
            Filterable => 0,
        },
        'MIMEBase_To' => {
            Label      => 'To',
            Key        => 'MIMEBase_To',
            Type       => 'Text',
            Filterable => 0,
        },
        'MIMEBase_Cc' => {
            Label      => 'Cc',
            Key        => 'MIMEBase_Cc',
            Type       => 'Text',
            Filterable => 0,
        },
        'MIMEBase_Subject' => {
            Label      => 'Subject',
            Key        => 'MIMEBase_Subject',
            Type       => 'Text',
            Filterable => 1,
        },
        'MIMEBase_Body' => {
            Label      => 'Body',
            Key        => 'MIMEBase_Body',
            Type       => 'Text',
            Filterable => 1,
        },
        'MIMEBase_AttachmentName' => {
            Label      => 'Attachment Name',
            Key        => 'MIMEBase_AttachmentName',
            Type       => 'Text',
            Filterable => 0,
        },
    );

=cut

sub BackendSearchableFieldsGet {
    my ( $Self, %Param ) = @_;

    my %SearchableFields = (
        'MIMEBase_From' => {
            Label      => 'From',
            Key        => 'MIMEBase_From',
            Type       => 'Text',
            Filterable => 0,
        },
        'MIMEBase_To' => {
            Label      => 'To',
            Key        => 'MIMEBase_To',
            Type       => 'Text',
            Filterable => 0,
        },
        'MIMEBase_Cc' => {
            Label      => 'Cc',
            Key        => 'MIMEBase_Cc',
            Type       => 'Text',
            Filterable => 0,
        },
        'MIMEBase_Subject' => {
            Label      => 'Subject',
            Key        => 'MIMEBase_Subject',
            Type       => 'Text',
            Filterable => 1,
        },
        'MIMEBase_Body' => {
            Label      => 'Body',
            Key        => 'MIMEBase_Body',
            Type       => 'Text',
            Filterable => 1,
        },
    );

    if (
        $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Article::Backend::MIMEBase')->{IndexAttachmentNames}
        )
    {
        $SearchableFields{'MIMEBase_AttachmentName'} = {
            Label      => 'Attachment Name',
            Key        => 'MIMEBase_AttachmentName',
            Type       => 'Text',
            Filterable => 0,
        };
    }

    return %SearchableFields;
}

=head2 ArticleSearchableContentGet()

Get article attachment index as hash.

    my %Index = $BackendObject->ArticleSearchableContentGet(
        TicketID       => 123,   # (required)
        ArticleID      => 123,   # (required)
        DynamicFields  => 1,     # (optional) To include the dynamic field values for this article on the return structure.
        RealNames      => 1,     # (optional) To include the From/To/Cc fields with real names.
        UserID         => 123,   # (required)
    );

Returns:

    my %ArticleSearchData = {
        'From'    => {
            String     => 'Test User1 <testuser1@example.com>',
            Key        => 'From',
            Type       => 'Text',
            Filterable => 0,
        },
        'To'    => {
            String     => 'Test User2 <testuser2@example.com>',
            Key        => 'To',
            Type       => 'Text',
            Filterable => 0,
        },
        'Cc'    => {
            String     => 'Test User3 <testuser3@example.com>',
            Key        => 'Cc',
            Type       => 'Text',
            Filterable => 0,
        },
        'Subject'    => {
            String     => 'This is a test subject!',
            Key        => 'Subject',
            Type       => 'Text',
            Filterable => 1,
        },
        'Body'    => {
            String     => 'This is a body text!',
            Key        => 'Body',
            Type       => 'Text',
            Filterable => 1,
        }
    };

=cut

sub ArticleSearchableContentGet {
    my ( $Self, %Param ) = @_;

    for (qw(TicketID ArticleID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my %DataKeyMap = (
        'MIMEBase_From'    => 'From',
        'MIMEBase_To'      => 'To',
        'MIMEBase_Cc'      => 'Cc',
        'MIMEBase_Subject' => 'Subject',
        'MIMEBase_Body'    => 'Body',
    );

    my %ArticleData = $Self->ArticleGet(
        TicketID      => $Param{TicketID},
        ArticleID     => $Param{ArticleID},
        UserID        => $Param{UserID},
        DynamicFields => 0,
    );

    my %BackendSearchableFields = $Self->BackendSearchableFieldsGet();

    my %ArticleSearchData;

    FIELDKEY:
    for my $FieldKey ( sort keys %BackendSearchableFields ) {

        my $IndexString;

        # scan available attachment names and append the information
        if ( $FieldKey eq 'MIMEBase_AttachmentName' ) {

            my %AttachmentIndex = $Self->ArticleAttachmentIndex(
                ArticleID        => $Param{ArticleID},
                UserID           => $Param{UserID},
                ExcludePlainText => 1,
                ExcludeHTMLBody  => 1,
                ExcludeInline    => 1,
            );

            next FIELDKEY if !%AttachmentIndex;

            my @AttachmentNames;

            for my $AttachmentKey ( sort keys %AttachmentIndex ) {
                push @AttachmentNames, $AttachmentIndex{$AttachmentKey}->{Filename};
            }

            $IndexString = join ' ', @AttachmentNames;
        }

        $IndexString //= $ArticleData{ $DataKeyMap{$FieldKey} };

        next FIELDKEY if !IsStringWithData($IndexString);

        $ArticleSearchData{$FieldKey} = {
            String     => $IndexString,
            Key        => $BackendSearchableFields{$FieldKey}->{Key},
            Type       => $BackendSearchableFields{$FieldKey}->{Type} // 'Text',
            Filterable => $BackendSearchableFields{$FieldKey}->{Filterable} // 0,
        };
    }

    return %ArticleSearchData;
}

=head2 ArticleHasHTMLContent()

Returns 1 if article has HTML content.

    my $ArticleHasHTMLContent = $ArticleBackendObject->ArticleHasHTMLContent(
        TicketID  => 1,
        ArticleID => 2,
        UserID    => 1,
    );

Result:

    $ArticleHasHTMLContent = 1;     # or 0

=cut

sub ArticleHasHTMLContent {
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

    # Check if there is HTML body attachment.
    my %AttachmentIndexHTMLBody = $Self->ArticleAttachmentIndex(
        %Param,
        OnlyHTMLBody => 1,
    );

    my ($HTMLBodyAttachmentID) = sort keys %AttachmentIndexHTMLBody;

    return $HTMLBodyAttachmentID ? 1 : 0;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
