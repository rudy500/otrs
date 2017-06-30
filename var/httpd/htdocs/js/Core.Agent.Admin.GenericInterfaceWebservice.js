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
Core.Agent.Admin = Core.Agent.Admin || {};

/**
 * @namespace Core.Agent.Admin.GenericInterfaceWebservice
 * @memberof Core.Agent.Admin
 * @author OTRS AG
 * @description
 *      This namespace contains the special module functions for the GenericInterface webservice module.
 */
Core.Agent.Admin.GenericInterfaceWebservice = (function (TargetNS) {

    /**
     * @private
     * @name DialogData
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @member {Array}
     * @description
     *     This variable stores the parameters that are passed from the TT and contain all the data that the dialog needs.
     */
    var DialogData = [];

    /**
     * @name HideElements
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @description
     *      Hides specific DOM elements.
     */
    TargetNS.HideElements = function(){
        $('button.HideActionOnChange').parent().hide();
        $('.HideOnChange').hide();
        $('.HideLinkOnChange').contents().unwrap();
    };

    /**
     * @name Init
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @description
     *      This function initialize the module functionality.
     */
    TargetNS.Init = function () {
        var Action = Core.Config.Get('Subaction'),
            JSData = Core.Config.Get('JSData'),
            ActionName, ActionType, ElementSelector, ElementID, Webservice;

        TargetNS.WebserviceID = parseInt($('#WebserviceID').val(), 10);

        if (Action === "Add") {
            TargetNS.HideElements();
        }

        $('#DeleteButton').on('click', TargetNS.ShowDeleteDialog);
        $('#CloneButton').on('click', TargetNS.ShowCloneDialog);
        $('#ImportButton').on('click', TargetNS.ShowImportDialog);

        Webservice = Core.Config.Get('Webservice');

        $('#ProviderTransportProperties').on('click', function() {
            TargetNS.Redirect(Webservice.Transport, 'ProviderTransportList', {CommunicationType: 'Provider'});
        });

        $('#RequesterTransportProperties').on('click', function() {
            TargetNS.Redirect(Webservice.Transport, 'RequesterTransportList', {CommunicationType: 'Requester'});
        });

        $('#OperationList').on('change', function() {
            TargetNS.Redirect(Webservice.Operation, 'OperationList', {OperationType: $(this).val()});
        });

        $('#InvokerList').on('change', function() {
            TargetNS.Redirect(Webservice.Invoker, 'InvokerList', {InvokerType: $(this).val()});
        });

        $('.HideTrigger').on('change', function(){
            TargetNS.HideElements();
        });

        $('#SaveAndFinishButton').on('click', function(){
            $('#ReturnToWebservice').val(1);
        });

        // Initialize delete action dialog events
        for (ActionName in JSData) {

            ActionType = JSData[ActionName];
            ElementSelector = '#Delete' + ActionType + ActionName;
            ElementID = 'Delete' + ActionType + ActionName;

            TargetNS.BindDeleteActionDialog({
                ElementID: ElementID,
                ActionName: ActionName,
                ActionType: ActionType,
                ElementSelector: ElementSelector
            });
        }
    };

    /**
     * @name ShowDeleteDialog
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @param {Object} Event - The browser event object, e.g. of the clicked DOM element.
     * @description
     *      Shows a confirmation dialog to delete the webservice.
     */
    TargetNS.ShowDeleteDialog = function(Event){
        Core.UI.Dialog.ShowContentDialog(
            $('#DeleteDialogContainer'),
            Core.Language.Translate('Delete webservice'),
            '240px',
            'Center',
            true,
            [
                {
                     Label: Core.Language.Translate('Cancel'),
                     Function: function () {
                         Core.UI.Dialog.CloseDialog($('#DeleteDialog'));
                     }
                },

                {
                     Label: Core.Language.Translate('Delete'),
                     Function: function () {
                         var Data = {
                             Action: 'AdminGenericInterfaceWebservice',
                             Subaction: 'Delete',
                             WebserviceID: TargetNS.WebserviceID
                         };

                         Core.AJAX.FunctionCall(Core.Config.Get('CGIHandle'), Data, function (Response) {
                             if (!Response || !Response.Success) {
                                 alert(Core.Language.Translate('An error occurred during communication.'));
                                 return;
                             }

                             Core.App.InternalRedirect({
                                 Action: Data.Action,
                                 DeletedWebservice: Response.DeletedWebservice
                             });
                         }, 'json');

                     }
                }
            ]
        );

        Event.stopPropagation();
    };

    /**
     * @name ShowCloneDialog
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @param {Object} Event - The browser event object, e.g. of the clicked DOM element.
     * @description
     *      Shows a dialog to clone a webservice.
     */
    TargetNS.ShowCloneDialog = function(Event){

        var CurrentDate, CloneName;

        Core.UI.Dialog.ShowContentDialog(
            $('#CloneDialogContainer'),
            Core.Language.Translate('Clone webservice'),
            '240px',
            'Center',
            true
        );

        // init validation
        // Currently we have not a function to initialize the validation on a single form
        Core.Form.Validate.Init();

        // get current system time to define suggested the name of the cloned webservice
        CurrentDate = new Date();
        CloneName = $('#Name').val() + "-" + CurrentDate.getTime();

        // set the suggested name
        $('.CloneName').val(CloneName);

        // bind button actions
        $('#CancelCloneButtonAction').on('click', function() {
            Core.UI.Dialog.CloseDialog($('#CloneDialog'));
        });

        $('#CloneButtonAction').on('click', function() {
            $('#CloneForm').submit();
        });

        Event.stopPropagation();
    };

    /**
     * @name ShowImportDialog
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @param {Object} Event - The browser event object, e.g. of the clicked DOM element.
     * @description
     *      Shows a dialog to import a webservice.
     */
    TargetNS.ShowImportDialog = function(Event){

        Core.UI.Dialog.ShowContentDialog(
            $('#ImportDialogContainer'),
            Core.Language.Translate('Import webservice'),
            '240px',
            'Center',
            true
        );

        // init validation
        // Currently we have not a function to initialize the validation on a single form
        Core.Form.Validate.Init();

        $('#CancelImportButtonAction').on('click', function() {
            Core.UI.Dialog.CloseDialog($('#ImportDialog'));
        });

        $('#ImportButtonAction').on('click', function() {
            $('#ImportForm').submit();
        });

        Event.stopPropagation();
    };

    /**
     * @name Redirect
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @param {String} Config
     * @param {String} DataSource
     * @param {Object} Data
     * @description
     *      Redirects.
     */
    TargetNS.Redirect = function(Config, DataSource, Data) {
        var WebserviceConfigPart, Action, ConfigElement;

        // get configuration
        // after JS refactoring this is most probably already a config object
        // and not a config key anymore
        // keeping the old part for backwards compatibility (can be removed later)
        if (typeof Config === 'object') {
            WebserviceConfigPart = Config;
        }
        else {
            WebserviceConfigPart = Core.Config.Get(Config);
        }

        // get the Config Element name, if none it will have "null" value
        ConfigElement = $('#' + DataSource).val();

        // check is config element is a valid scring
        if (ConfigElement !== null) {

            // get action
            Action = WebserviceConfigPart[ ConfigElement ];

            $.extend(Data, {
                Action: Action,
                Subaction: 'Add',
                WebserviceID: TargetNS.WebserviceID
            });

            // redirect to correct url
            Core.App.InternalRedirect(Data);
        }
    };

    /**
     * @name ShowDeleteActionDialog
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @param {Object} Event - The browser event object, e.g. of the clicked DOM element.
     * @description
     *      Shows a dialog to delete operation or invoker.
     */
    TargetNS.ShowDeleteActionDialog = function(Event){
        var LocalDialogData, ActionType, DialogTitle;

        // get global saved DialogData for this function
        LocalDialogData = DialogData[$(Event.target).attr('id')];
        if ($(Event.target).hasClass('DeleteOperation')) {
            ActionType = 'Operation';
            DialogTitle = Core.Language.Translate('Delete operation');
        }
        else {
            ActionType = 'Invoker';
            DialogTitle = Core.Language.Translate('Delete invoker');
        }

        Core.UI.Dialog.ShowContentDialog(
            $('#Delete' + ActionType + 'DialogContainer'),
            DialogTitle,
            '240px',
            'Center',
            true,
            [
               {
                   Label: Core.Language.Translate('Cancel'),
                   Class: 'Primary',
                   Function: function () {
                       Core.UI.Dialog.CloseDialog($('#Delete' + ActionType + 'Dialog'));
                   }
               },
               {
                   Label: Core.Language.Translate('Delete'),
                   Function: function () {
                       var Data = {
                            Action: 'AdminGenericInterfaceWebservice',
                            Subaction: 'DeleteAction',
                            WebserviceID: TargetNS.WebserviceID,
                            ActionType: LocalDialogData.ActionType,
                            ActionName: LocalDialogData.ActionName
                        };
                        Core.AJAX.FunctionCall(Core.Config.Get('CGIHandle'), Data, function (Response) {
                            if (!Response || !Response.Success) {
                                alert(Core.Language.Translate('An error occurred during communication.'));
                                return;
                            }

                            Core.App.InternalRedirect({
                                Action: Data.Action,
                                Subaction: 'Change',
                                WebserviceID: TargetNS.WebserviceID
                            });

                        }, 'json');

                       Core.UI.Dialog.CloseDialog($('#Delete' + ActionType + 'Dialog'));
                   }
               }
           ]
        );

        Event.stopPropagation();
        Event.preventDefault();
    };

    /**
     * @name BindDeleteActionDialog
     * @memberof Core.Agent.Admin.GenericInterfaceWebservice
     * @function
     * @param {Object} Data - A control structure that contains the jQueryObjectID, jQueryObjectSelector the ActionType and the ActionName.
     * @description
     *      This function binds a "trash can" link from the action table to the
     *      function that opens a dialog to delete the action
     */
    TargetNS.BindDeleteActionDialog = function (Data) {
        DialogData[Data.ElementID] = Data;

        // binding a click event to the defined element
        $(DialogData[Data.ElementID].ElementSelector).on('click', TargetNS.ShowDeleteActionDialog);
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.Agent.Admin.GenericInterfaceWebservice || {}));
