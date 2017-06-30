// --
// Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.TicketBulk
 * @memberof Core.Agent
 * @author OTRS AG
 * @description
 *      This namespace contains special module functions for the TicketBulk.
 */
Core.Agent.TicketBulk = (function (TargetNS) {

    /**
     * @name Init
     * @memberof Core.Agent.TicketBulk
     * @function
     * @description
     *      This function initializes the functionality for the TicketBulk screen.
     */
    TargetNS.Init = function () {

        var TicketBulkURL = Core.Config.Get('TicketBulkURL');

        // bind radio and text input fields
        $('#MergeTo').on('blur', function() {
            if ($(this).val()) {
                $('#OptionMergeTo').prop('checked', true);
            }
        });

        // Update owner and responsible fields on queue change.
        $('#QueueID').on('change', function () {
            Core.AJAX.FormUpdate($('.Validate'), 'AJAXUpdate', 'QueueID', ['OwnerID', 'ResponsibleID']);
        });

        // execute function in the parent window
        Core.UI.Popup.ExecuteInParentWindow(function(WindowObject) {
            WindowObject.Core.UI.Popup.FirePopupEvent('URL', { URL: TicketBulkURL }, false);
        });

        // get the Recipients on expanding of the email widget
        $('#EmailSubject').closest('.WidgetSimple').find('.Header .Toggle a').on('click', function() {

            // if the spinner is still there, we want to load the recipients list
            if ($('#EmailRecipientsList i.fa-spinner:visible').length) {

                Core.AJAX.FunctionCall(
                    Core.Config.Get('CGIHandle'),
                    {
                        'Action'    : 'AgentTicketBulk',
                        'Subaction' : 'AJAXRecipientList',
                        'TicketIDs' : Core.JSON.Stringify(Core.Config.Get('ValidTicketIDs'))
                    },
                    function(Response) {
                        var Recipients = Core.JSON.Parse(Response),
                            TextShort = '',
                            TextFull = '',
                            Counter;

                        if (Recipients.length <= 3) {
                            $('#EmailRecipientsList').text(Recipients.join(', '));
                        }
                        else {
                            for (Counter = 0; Counter < 3; Counter++) {
                                TextShort += Recipients[Counter];
                                if (Counter < 2) {
                                    TextShort += ', ';
                                }
                            }

                            for (Counter = 3; Counter < Recipients.length; Counter++) {
                                if (Counter < Recipients.length) {
                                    TextFull += ', ';
                                }
                                TextFull += Recipients[Counter];
                            }

                            $('#EmailRecipientsList').text(TextShort);
                            $('#EmailRecipientsList')
                                .append('<a href="#" class="Expand"></a>')
                                .find('a')
                                .on('click', function() {

                                    $(this).hide();
                                    $(this).nextAll('span, a').fadeIn();
                                    return false;
                                })
                                .text(Core.Language.Translate(" ...and %s more", Recipients.length - 3))
                                .closest('span')
                                .append('<span />')
                                .find('span')
                                .text(TextFull)
                                .parent()
                                .append('<a href="#" class="Collapse"></a>')
                                .find('a.Collapse')
                                .on('click', function() {

                                    $(this)
                                        .hide()
                                        .prev('span')
                                        .hide()
                                        .prev('a')
                                        .fadeIn();

                                    return false;
                                })
                                .text(Core.Language.Translate(" ...show less"));
                        }
                    }
                );
            }
        });
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.Agent.TicketBulk || {}));
