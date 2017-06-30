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
 * @namespace Core.Agent.TicketHistory
 * @memberof Core.Agent
 * @author OTRS AG
 * @description
 *      This namespace contains the TicketHistory functions.
 */
Core.Agent.TicketHistory = (function (TargetNS) {

    /**
     * @name Init
     * @memberof Core.Agent.TicketHistory
     * @function
     * @description
     *      This function initializes the functionality for the TicketHistory screen.
     */
    TargetNS.Init = function () {

        // bind click event on ZoomView link
        $('a.LinkZoomView').on('click', function () {
            var that = this;
            Core.UI.Popup.ExecuteInParentWindow(function(WindowObject) {
                WindowObject.Core.UI.Popup.FirePopupEvent('URL', { URL: $(that).attr('href')});
            });
            Core.UI.Popup.ClosePopup();
        });
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.Agent.TicketHistory || {}));
