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
 * @namespace Core.Agent.Admin.GenericInterfaceTransportHTTPSOAP
 * @memberof Core.Agent.Admin
 * @author OTRS AG
 * @description
 *      This namespace contains the special module functions for the GenericInterface Transport HTTP SOAP module.
 */
Core.Agent.Admin.GenericInterfaceTransportHTTPSOAP = (function (TargetNS) {

    /**
     * @name RemoveValue
     * @memberof Core.Agent.Admin.GenericInterfaceTransportHTTPSOAP
     * @function
     * @returns {Boolean} Returns false.
     * @param {String} IDSelector - ID of the pressed remove value button.
     * @description
     *      This function removes a value from possible values list and creates a stub input so
     *      the server can identify if a value is empty or deleted (useful for server validation)
     *      It also deletes the Value from the DefaultValues list
     */
    TargetNS.RemoveValue = function (IDSelector){

        // copy HTML code for an input replacement for the deleted value
        var $Clone = $('.DeletedValue').clone(),

        // get the index of the value to delete (its always the second element (1) in this RegEx
        $ObjectIndex = IDSelector.match(/.+_(\d+)/)[1],

        // get the key name to remove it from the defaults select
        $Key = $('#Key_' + $ObjectIndex).val();

        // set the input replacement attributes to match the deleted original value
        // new value and other controls are not needed anymore
        $Clone.attr('id', 'Key' + '_' + $ObjectIndex);
        $Clone.attr('name', 'Key' + '_' + $ObjectIndex);
        $Clone.removeClass('DeletedValue');

        // add the input replacement to the mapping type so it can be parsed and distinguish from
        // empty values by the server
        $('#' + IDSelector).closest('fieldset').append($Clone);

        // remove the value from default list
        if ($Key !== ''){
            $('#DefaultValue').find("option[value='" + $Key + "']").remove();
            $('#DefaultValue').trigger('redraw.InputField');
        }

        // remove possible value
        $('#' + IDSelector).parent().remove();

        return false;
    };

    /**
     * @name AddValue
     * @memberof Core.Agent.Admin.GenericInterfaceTransportHTTPSOAP
     * @function
     * @returns {Boolean} Returns false
     * @param {Object} ValueInsert - HTML container of the value mapping row.
     * @description
     *      This function adds a new value to the possible values list
     */
    TargetNS.AddValue = function (ValueInsert) {

        // clone key dialog
        var $Clone = $('.ValueTemplate').clone(),
            ValueCounter = $('#ValueCounter').val();

        // increment key counter
        ValueCounter++;

        // remove unnecessary classes
        $Clone.removeClass('Hidden ValueTemplate');

        // add needed class
        $Clone.addClass('ValueRow');

        // copy values and change ids and names
        $Clone.find(':input, a.RemoveButton').each(function(){
            var ID = $(this).attr('id');
            $(this).attr('id', ID + '_' + ValueCounter);
            $(this).attr('name', ID + '_' + ValueCounter);

            $(this).addClass('Validate_Required');

            // set error controls
            $(this).parent().find('#' + ID + 'Error').attr('id', ID + '_' + ValueCounter + 'Error');
            $(this).parent().find('#' + ID + 'Error').attr('name', ID + '_' + ValueCounter + 'Error');

            $(this).parent().find('#' + ID + 'ServerError').attr('id', ID + '_' + ValueCounter + 'ServerError');
            $(this).parent().find('#' + ID + 'ServerError').attr('name', ID + '_' + ValueCounter + 'ServerError');

            // add event handler to remove button
            if($(this).hasClass('RemoveButton')) {
                // bind click function to remove button
                $(this).on('click', function () {
                    TargetNS.RemoveValue($(this).attr('id'));
                    return false;
                });
            }
        });

        $Clone.find('label').each(function(){
            var FOR = $(this).attr('for');
            $(this).attr('for', FOR + '_' + ValueCounter);
        });

        // prepend to container
        ValueInsert.prepend($Clone);

        // set new value for KeyName
        $('#ValueCounter').val(ValueCounter);

        return false;
    };

    /**
     * @name Init
     * @memberof Core.Agent.Admin.GenericInterfaceTransportHTTPSOAP
     * @function
     * @description
     *      This function binds events to certain actions
     */
    TargetNS.Init = function () {

        // bind change function to Request Name Scheme field
        $('#RequestNameScheme').on('change', function(){
            if ($(this).val() === 'Append' || $(this).val() === 'Replace') {
                $('.RequestNameFreeTextField').removeClass('Hidden');
                $('#RequestNameFreeText').addClass('Validate_Required');
            }
            else {
                $('.RequestNameFreeTextField').addClass('Hidden');
                $('#RequestNameFreeText').removeClass('Validate_Required');
            }
        });

        // bind change function to Response Name Scheme field
        $('#ResponseNameScheme').on('change', function(){
            if ($(this).val() === 'Append' || $(this).val() === 'Replace') {
                $('.ResponseNameFreeTextField').removeClass('Hidden');
                $('#ResponseNameFreeText').addClass('Validate_Required');
            }
            else {
                $('.ResponseNameFreeTextField').addClass('Hidden')
                $('#ResponseNameFreeText').removeClass('Validate_Required');
            }
        });

        // bind change function to SOAP Action field
        $('#SOAPAction').on('change', function(){
            if ($(this).val() === 'Yes') {
                $('.SOAPActionField').removeClass('Hidden');
            }
            else {
                $('.SOAPActionField').addClass('Hidden');
            }
        });

        // bind change function to Authentication field
        $('#Authentication').on('change', function(){
            if ($(this).val() === 'BasicAuth') {
                $('.BasicAuthField').removeClass('Hidden');
                $('.BasicAuthField').find('#UserName').each(function(){
                    $(this).addClass('Validate_Required');
                });
            }
            else {
                $('.BasicAuthField').addClass('Hidden');
                $('.BasicAuthField').find('#User').each(function(){
                    $(this).removeClass('Validate_Required');
                });
            }
        });

        // bind change function to Use SSL field
        $('#UseSSL').on('change', function(){
            if ($(this).val() === 'Yes') {
                $('.SSLField').removeClass('Hidden');
                $('.SSLField').find('#SSLP12Certificate').each(function(){
                    $(this).addClass('Validate_Required');
                });
                $('.SSLField').find('#SSLP12Password').each(function(){
                    $(this).addClass('Validate_Required');
                });
            }

            else {
                $('.SSLField').addClass('Hidden');
                $('.SSLField').find('#SSLP12Certificate').each(function(){
                    $(this).removeClass('Validate_Required');
                });
                $('.SSLField').find('#SSLP12Password').each(function(){
                    $(this).removeClass('Validate_Required');
                });
            }
        });

        // special handling for value counter
        $('.ValueRow :input[name^="Key"]').each(function(i){

            // set value counter
            $('#ValueCounter').val(i + 1);
        })

        //bind click function to add button
        $('#AddValue').on('click', function () {
            TargetNS.AddValue(
                $(this).closest('fieldset').find('.ValueInsert')
            );
            return false;
        });

        //bind click function to remove button
        $('.ValueRemove').on('click', function () {
            TargetNS.RemoveValue($(this).attr('id'));
            return false;
        });

        // bind click function to Save and finish button
        $('#SaveAndFinishButton').on('click', function(){
            $('#ReturnToWebservice').val(1);
        });

        Core.Agent.SortedTree.Init($('.SortableList'), $('#TransportConfigForm'), $('#Sort'), Core.Config.Get('SortData'));
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.Agent.Admin.GenericInterfaceTransportHTTPSOAP || {}));
