// --
// Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};

/**
 * @namespace Core.UI
 * @memberof Core
 * @author OTRS AG
 * @description
 *      This namespace contains all UI functions.
 */
Core.UI = (function (TargetNS) {

    /**
     * @private
     * @name IDGeneratorCount
     * @memberof Core.UI
     * @member {Number}
     * @description
     *      Counter for automatic HTML element ID generation.
     */
    var IDGeneratorCount = 0;

    /**
     * @name InitWidgetActionToggle
     * @memberof Core.UI
     * @function
     * @description
     *      This function initializes the toggle mechanism for all widgets with a WidgetAction toggle icon.
     */
    TargetNS.InitWidgetActionToggle = function () {
        $(".WidgetAction.Toggle > a")
            .each(function () {
                var $WidgetElement = $(this).closest("div.Header").parent('div'),
                    ContentDivID = TargetNS.GetID($WidgetElement.children('.Content'));

                // fallback to Expanded if default state was not given
                if (!$WidgetElement.hasClass('Expanded') && !$WidgetElement.hasClass('Collapsed')){
                    $WidgetElement.addClass('Expanded');
                }

                $(this)
                    .attr('aria-controls', ContentDivID)
                    .attr('aria-expanded', $WidgetElement.hasClass('Expanded'));
            })
            .off('click.WidgetToggle')
            .on('click.WidgetToggle', function (Event) {
                var $WidgetElement = $(this).closest("div.Header").parent('div'),
                    Animate = $WidgetElement.hasClass('Animate'),
                    $that = $(this);

                function ToggleWidget() {
                    $WidgetElement
                        .toggleClass('Collapsed')
                        .toggleClass('Expanded')
                        .end()
                        .end()
                        .attr('aria-expanded', $that.closest("div.Header").parent('div').hasClass('Expanded'));
                        Core.App.Publish('Event.UI.ToggleWidget', [$WidgetElement]);
                }

                if (Animate) {
                    $WidgetElement.addClass('AnimationRunning').find('.Content').slideToggle("fast", function () {
                        ToggleWidget();
                        $WidgetElement.removeClass('AnimationRunning');
                    });
                } else {
                    ToggleWidget();
                }

                Event.preventDefault();
            });
    };

    /**
     * @name WidgetOverlayShow
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $Widget - Widget element
     * @param {String} Type - type of icon which should be displayed (currently only 'Loading' is possible)
     * @description
     *      This function covers a given widget with an overlay
     */
    TargetNS.WidgetOverlayShow = function ($Widget, Type) {

        var IconClass = 'fa-check'
        if (Type || Type == 'Loading') {
            IconClass = 'fa-circle-o-notch fa-spin'
        }

        $Widget
            .addClass('HasOverlay')
            .find('.Content')
            .prepend('<div class="Overlay" style="display: none;"><i class="fa ' + IconClass + '"></i></div>')
            .children('.Overlay')
            .fadeIn();
    };

    /**
     * @name WidgetOverlayHide
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $Widget - Widget element
     * @param {Boolean} Switch - Whether the overlay should show a success icon before being removed
     * @description
     *      This function removes an overlay from a given widget
     */
    TargetNS.WidgetOverlayHide = function ($Widget, Switch) {

        if (Switch) {
            $Widget
                .find('.Overlay i')
                .fadeOut()
                .parent()
                .append('<i class="fa fa-check" style="display: none;" />')
                .find('i:last-child')
                .fadeIn()
                .parent()
                .delay(1000)
                .fadeOut(function() {
                    $Widget.removeClass('HasOverlay');
                    $(this).remove();
                });
        }
        else {
            $Widget
                .find('.Overlay')
                .fadeOut(function() {
                    $Widget.removeClass('HasOverlay');
                    $(this).remove();
                });
        }
    };

    /**
     * @name InitMessageBoxClose
     * @memberof Core.UI
     * @function
     * @description
     *      This function initializes the close buttons for the message boxes that show server messages.
     */
    TargetNS.InitMessageBoxClose = function () {
        $(".MessageBox > a.Close")
            .off('click.MessageBoxClose')
            .on('click.MessageBoxClose', function (Event) {
                $(this).parent().remove();
                Event.preventDefault();
            });
    };

    /**
     * @name GetID
     * @memberof Core.UI
     * @function
     * @returns {String} ID of the element
     * @param {jQueryObject} $Element - The HTML element
     * @description
     *      Returns the ID of the Element and creates one for it if nessessary.
     */
    TargetNS.GetID = function ($Element) {
        var ID;

        function GenerateID() {
            return 'Core_UI_AutogeneratedID_' + IDGeneratorCount++;
        }

        if ($Element) {
            if ($Element.attr('id')) {
                ID = $Element.attr('id');
            }
            else {
                ID = GenerateID();
                $Element.attr('id', ID);
            }
        }
        else {
            ID = GenerateID();
        }

        return ID;
    };

    /**
     * @name ToggleTwoContainer
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $Element1 - First container element.
     * @param {jQueryObject} $Element2 - Second container element.
     * @description
     *      This functions toggles two Containers with a nice slide effect.
     */
    TargetNS.ToggleTwoContainer = function ($Element1, $Element2) {
        if (isJQueryObject($Element1, $Element2) && $Element1.length && $Element2.length) {
            $Element1.slideToggle('fast', function () {
                $Element2.slideToggle('fast', function() {
                    Core.UI.InputFields.InitSelect($Element2.find('.Modernize'));
                });
                Core.UI.InputFields.InitSelect($Element1.find('.Modernize'));
            });
        }
    };

    /**
     * @name RegisterToggleTwoContainer
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $ClickedElement
     * @param {jQueryObject} $Element1 - First container element.
     * @param {jQueryObject} $Element2 - Second container element.
     * @description
     *      Registers click event to toggle the container.
     */
    TargetNS.RegisterToggleTwoContainer = function ($ClickedElement, $Element1, $Element2) {
        if (isJQueryObject($ClickedElement) && $ClickedElement.length) {
            $ClickedElement.click(function () {
                var $ContainerObj = $(this).closest('.WidgetSimple').find('.AllocationListContainer'),
                    FieldName,
                    Data = {};

                if ($Element1.is(':visible')) {
                    TargetNS.ToggleTwoContainer($Element1, $Element2);
                }
                else {
                    TargetNS.ToggleTwoContainer($Element2, $Element1);
                }

                Data.Columns = {};
                Data.Order = [];

                // Get initial columns order (see bug#10683).
                $ContainerObj.find('.AvailableFields').find('li').each(function() {
                    FieldName = $(this).attr('data-fieldname');
                    Data.Columns[FieldName] = 0;
                });

                $ContainerObj.find('.AssignedFields').find('li').each(function() {
                    FieldName = $(this).attr('data-fieldname');
                    Data.Columns[FieldName] = 1;
                    Data.Order.push(FieldName);
                });
                $ContainerObj.closest('form').find('.ColumnsJSON').val(Core.JSON.Stringify(Data));

                return false;
            });
        }
    };

    /**
     * @name ScrollTo
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $Element
     * @description
     *      Scrolls the active window until an element is visible.
     */
    TargetNS.ScrollTo = function ($Element) {
        if (isJQueryObject($Element) && $Element.length) {
            window.scrollTo(0, $Element.offset().top);
        }
    };

    /**
     * @name ShowNotification
     * @memberof Core.UI
     * @function
     * @param {String} Text the text which should be shown in the notification (untranslated)
     * @param {String} Type Error|Notice (default)
     * @param {String} Link the (internal) URL to which the notification text should point
     * @param {Function} Callback function which should be executed once the notification was hidden
     * @returns {Boolean} true or false depending on if the notification could be shown or not
     * @description
     *      Displays a notification on top of the page.
     */
    TargetNS.ShowNotification = function (Text, Type, Link, Callback) {

        var $ExistingNotifications,
            $NotificationObj;

        if (!Text) {
            return false;
        }

        if (!Type) {
            Type = 'Notice';
        }

        // check if a similar notification is already shown,
        // in this case do nothing
        $ExistingNotifications = $('.MessageBox').filter(
            function() {
                var Match = 0;
                if ($(this).find('a').text().indexOf(Core.Language.Translate(Text)) > 0 && $(this).hasClass(Type)) {
                    Match = 1;
                }
                return Match;
            }
        );

        if ($ExistingNotifications.length) {
            return false;
        }

        if (Link) {
            Link = Core.Config.Get('Baselink') + Link;
        }

        // render the notification
        $NotificationObj = $(
            Core.Template.Render("Agent/Notification", {
                Class: Type,
                URL: Link,
                Text: Core.Language.Translate(Text)
            })
        );

        // hide it initially
        $NotificationObj.hide();

        // if there are other notifications, append the new on the bottom
        if ($('.MessageBox:visible').length) {
            $NotificationObj.insertAfter('.MessageBox:visible:last');
        }
        // otherwise insert it on top
        else {
            $NotificationObj.insertAfter('#NavigationContainer');
        }

        // show it finally with animation and execute possible callbacks
        $NotificationObj.slideDown(function() {
            if ($.isFunction(Callback)) {
                Callback();
            }
        });

        return true;
    };

    /**
     * @name HideNotification
     * @memberof Core.UI
     * @function
     * @param {String} Text the text by which the notification can be recognized (untranslated).
     * @param {String} Type Error|Notice
     * @param {Function} Callback function which should be executed once the notification was hidden
     * @returns {Boolean} true or false depending on if the notification could be removed or not
     * @description
     *      Hides a certain notification.
     */
    TargetNS.HideNotification = function (Text, Type, Callback) {

        if (!Text || !Type) {
            return false;
        }

        $('.MessageBox').filter(
            function() {
                if ($(this).find('a').text().indexOf(Core.Language.Translate(Text)) > 0 && $(this).hasClass(Type)) {
                    $(this).slideUp(function() {
                        $(this).remove();
                        if ($.isFunction(Callback)) {
                            Callback();
                        }
                    })
                }
            }
        );

        return true;
    }

    /**
     * @name InitCheckboxSelection
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $Element - The element selector which describes the element(s) which surround the checkboxes.
     * @description
     *      This function initializes a click event for tables / divs with checkboxes.
     *      If you click in the table cell / div around the checkbox the checkbox will be selected.
     *      A possible MasterAction will not be executed.
     */
    TargetNS.InitCheckboxSelection = function ($Element) {
        if (!$Element.length) {
            return;
        }

        // e.g. 'table td.Checkbox' or 'div.Checkbox'
        $Element.off('click.CheckboxSelection').on('click.CheckboxSelection', function (Event) {
            var $Checkbox = $(this).find('input[type="checkbox"]');

            if (!$Checkbox.length) {
                return;
            }

            if ($(Event.target).is('input[type="checkbox"]')) {
                return;
            }

            Event.stopPropagation();

            $Checkbox
                .prop('checked', !$Checkbox.prop('checked'))
                .triggerHandler('click');


        });
    };

    /**
     * @name Animate
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $Element - The element to animate.
     * @param {String} Type - The animation type as defined in Core.Animations.css, e.g. 'Shake'
     * @description
     *      Animate an element on demand using a css-based animation of the given type
     */
    TargetNS.Animate = function ($Element, Type) {
        if (!$Element.length || !Type) {
            return;
        }
        $Element.addClass('Animation' + Type);
    };

    /**
     * @name InitMasterAction
     * @memberof Core.UI
     * @function
     * @description
     *      Extend click event to the whole table row.
     */
    TargetNS.InitMasterAction = function () {
        $('.MasterAction').click(function (Event) {
            var $MasterActionLink = $(this).find('.MasterActionLink');

            // only act if the link was not clicked directly
            if (Event.target !== $MasterActionLink.get(0)) {
                window.location = $MasterActionLink.attr('href');
                return false;
            }
        });
    };

    /**
     * @name InitStickyWidget
     * @memberof Core.UI
     * @function
     * @param {jQueryObject} $Element - The element to animate.
     * @param {String} Type - The animation type as defined in Core.Animations.css, e.g. 'Shake'
     * @description
     *      Animate an element on demand using a css-based animation of the given type
     */
    TargetNS.InitStickyElement = function () {

        var Position = $('.StickyElement').offset(),
            Width = $('.StickyElement').outerWidth(),
            $Element = $('.StickyElement'),
            Visible = $('.StickyElement').is(':visible');

        if (!Visible) {
            return;
        }

        // if we are on a mobile environment, don't use sticky elements
        if (Core.App.Responsive.IsSmallerOrEqual(Core.App.Responsive.GetScreenSize(), 'ScreenL')) {
            return;
        }

        if (!$Element.length || $Element.length > 1) {
            return;
        }

        function RepositionElement($Element, Width) {
            if ($(window).scrollTop() > Position.top) {

                if ($Element.css('position') === 'fixed') {
                    return false;
                }

                $Element.css({
                    'position' : 'fixed',
                    'top'      : '9px',
                    'width'    : Width
                });
            }
            else {
                $Element.css('position', 'static');
            }
        }

        RepositionElement($Element, Width);
        $(window).off('scroll.StickyElement').on('scroll.StickyElement', function() {
            RepositionElement($Element, Width);
        });
    };

    /**
     * @name Init
     * @memberof Core.UI
     * @function
     * @description
     *      Initializes the namespace.
     */
    TargetNS.Init = function() {
        Core.UI.InitWidgetActionToggle();
        Core.UI.InitMessageBoxClose();
        Core.UI.InitMasterAction();
        Core.UI.InitStickyElement();
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_GLOBAL');

    return TargetNS;
}(Core.UI || {}));
