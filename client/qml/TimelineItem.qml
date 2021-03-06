import QtQuick 2.2
import QtQuick.Controls 1.4
import QMatrixClient 1.0

Item {
    // Supplementary components

    SystemPalette { id: defaultPalette; colorGroup: SystemPalette.Active }
    SystemPalette { id: disabledPalette; colorGroup: SystemPalette.Disabled }
    Settings {
        id: settings
        readonly property bool condense_chat: value("UI/condense_chat", false)
        readonly property bool show_noop_events: value("UI/show_noop_events", false)
        readonly property bool autoload_images: value("UI/autoload_images", true)
        readonly property string highlight_color: value("UI/highlight_color", "orange")
        readonly property string render_type: value("UI/Fonts/render_type", "NativeRendering")
        readonly property int animations_duration_ms: value("UI/animations_duration_ms", 400)
        readonly property int fast_animations_duration_ms: animations_duration_ms / 2
        readonly property bool show_author_avatars: value("UI/show_author_avatars", false)
    }

    // Property interface

    /** Determines whether the view is moving at the moment */
    property var view
    property bool moving: view.moving

    // TimelineItem definition

    visible: marks != "hidden" || settings.show_noop_events
    height: childrenRect.height

    readonly property bool sectionVisible: section !== aboveSection
    readonly property bool redacted: marks == "redacted"
    readonly property string textColor:
        redacted ? disabledPalette.text :
        highlight ? settings.highlight_color :
        (["state", "notice", "other"].indexOf(eventType) >= 0) ?
                disabledPalette.text : defaultPalette.text
    readonly property string authorName:
        room.roomMembername(author.id)

    // A message is considered shown if its bottom is within the
    // viewing area of the timeline.
    readonly property bool shown:
        y + message.height - 1 > view.contentY &&
        y + message.height - 1 < view.contentY + view.height

    onShownChanged:
        controller.onMessageShownChanged(eventId, shown)

    Component.onCompleted: {
        if (shown)
            shownChanged(true);
    }

    NumberAnimation on opacity {
        from: 0; to: 1
        // Reduce duration when flicking/scrolling
        duration: moving ? settings.fast_animations_duration_ms :
                           settings.animations_duration_ms
        // Give time for chatView.displaced to complete
        easing.type: Easing.InExpo
    }
//            NumberAnimation on height {
//                from: 0; to: childrenRect.height
//                duration: settings.fast_animations_duration_ms
//                easing.type: Easing.OutQuad
//            }

    Column {
        id: fullMessage
        width: parent.width

        Rectangle {
            width: parent.width
            height: childrenRect.height + 2
            visible: sectionVisible
            color: defaultPalette.window
            Label {
                font.bold: true
                renderType: settings.render_type
                text: section
            }
        }
        Loader {
            id: detailsAreaLoader
//            asynchronous: true // https://bugreports.qt.io/browse/QTBUG-50992
            active: visible
            visible: false // Controlled by showDetailsButton
            opacity: 0
            width: parent.width

            sourceComponent: detailsArea
        }

        Item {
            id: message
            width: parent.width
            height: childrenRect.height

            Label {
                id: timelabel
                anchors.top: textField.top
                anchors.left: parent.left

                color: disabledPalette.text
                renderType: settings.render_type

                text: "<" +
                      time.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                      + ">"
            }
            Image {
                id: authorAvatar
                visible: settings.show_author_avatars && author.avatarMediaId
                anchors.top: textField.top
                anchors.left: timelabel.right
                anchors.leftMargin: 3
                height: showDetailsButton.height
                fillMode: Image.PreserveAspectFit

                sourceSize.height: showDetailsButton.height
                source: visible ? "image://mtx/" + author.avatarMediaId : ""
            }

            Label {
                id: authorLabel
                width: 120 - authorAvatar.width
                anchors.top: textField.top
                anchors.left: authorAvatar.right
                anchors.leftMargin: 3
                horizontalAlignment: if( ["other", "emote", "state"]
                                             .indexOf(eventType) >= 0 )
                                     { Text.AlignRight }
                elide: Text.ElideRight

                color: textColor
                renderType: settings.render_type

                text: eventType == "state" || eventType == "emote" ?
                          "* " + authorName :
                      eventType != "other" ? authorName : "***"
            }
            MouseArea {
                anchors.left: authorAvatar.left
                anchors.right: authorLabel.right
                anchors.top: authorLabel.top
                anchors.bottom:  authorLabel.bottom
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    controller.insertMention(authorName)
                    controller.focusInput()
                }
            }
            TextEdit {
                id: textField
                anchors.left: authorLabel.right
                anchors.leftMargin: 3
                anchors.right: showDetailsButton.left
                anchors.rightMargin: 3

                selectByMouse: true;
                readOnly: true;
                textFormat: TextEdit.RichText
                text: display
                wrapMode: Text.Wrap;
                color: textColor
                renderType: settings.render_type

                MouseArea {
                    anchors.fill: parent
                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor
                                                    : Qt.IBeamCursor
                    acceptedButtons: Qt.NoButton
                }
                // TODO: In the code below, links should be resolved
                // with Qt.resolvedLink, once we figure out what
                // to do with relative URLs (note: www.google.com
                // is a relative URL, https://www.google.com is not).
                // Instead of Qt.resolvedUrl (and, most likely,
                // QQmlAbstractUrlInterceptor to convert URLs)
                // we might just prefer to do the whole resolving
                // in C++.
                onHoveredLinkChanged:
                    controller.showStatusMessage(hoveredLink)

                onLinkActivated: Qt.openUrlExternally(link)
            }
            Loader {
                active: eventType == "image"

                anchors.top: textField.bottom
                anchors.left: textField.left
                anchors.right: textField.right

                sourceComponent: ImageContent {
                    imageSourceSize:
                        !progressInfo.active && content.info.thumbnail_info ?
                            Qt.size(content.info.thumbnail_info.h,
                                    content.info.thumbnail_info.w) :
                            Qt.size(content.info.w, content.info.h)
                    imageSource: downloaded ? progressInfo.localPath :
                                 content.info.thumbnail_info ?
                                    "image://mtx/" + content.thumbnailMediaId : ""
                    autoload: settings.autoload_images
                }
            }
            Loader {
                active: eventType == "file"

                anchors.top: textField.bottom
                anchors.left: textField.left
                anchors.right: textField.right
                height: childrenRect.height

                sourceComponent: FileContent { }
            }
            ToolButton {
                id: showDetailsButton
                anchors.top: textField.top
                anchors.right: parent.right
                height: settings.condense_chat && textField.visible ?
                            Math.min(implicitHeight, textField.height) :
                            implicitHeight

                text: "..."

                action: Action {
                    id: showDetails

                    tooltip: "Show details and actions"
                    checkable: true
                }

                onCheckedChanged: SequentialAnimation {
                    PropertyAction {
                        target: detailsAreaLoader; property: "visible"
                        value: true
                    }
                    NumberAnimation {
                        target: detailsAreaLoader; property: "opacity"
                        to: showDetails.checked
                        duration: settings.fast_animations_duration_ms
                        easing.type: Easing.OutQuad
                    }
                    PropertyAction {
                        target: detailsAreaLoader; property: "visible"
                        value: showDetails.checked
                    }
                }
            }
        }
    }
    Rectangle {
        id: readMarkerLine
        color: defaultPalette.highlight
        width: readMarker && parent.width
        height: 1
        anchors.bottom: fullMessage.bottom
        Behavior on width { NumberAnimation {
            duration: settings.animations_duration_ms
            easing.type: Easing.OutQuad
        }}
    }

    // Components loaded on demand

    Component {
        id: detailsArea

        Rectangle {
            height: childrenRect.height
            radius: 5

            color: defaultPalette.button
            border.color: defaultPalette.mid

            readonly property url evtLink:
                "https://matrix.to/#/" + room.id + "/" + eventId
            property string sourceText: toolTip

            Item {
                id: detailsHeader
                width: parent.width
                height: childrenRect.height
                anchors.top: parent.top

                TextEdit {
                    text: "<" + time.toLocaleString(Qt.locale(), Locale.ShortFormat) + ">"
                    font.bold: true
                    renderType: settings.render_type
                    readOnly: true
                    selectByKeyboard: true; selectByMouse: true

                    anchors.left: parent.left
                    anchors.leftMargin: 3
                    anchors.verticalCenter: copyLinkButton.verticalCenter
                    z: 1
                }
                TextEdit {
                    text: "<a href=\"" + evtLink + "\">"+ eventId + "</a>"
                    textFormat: Text.RichText
                    font.bold: true
                    renderType: settings.render_type
                    horizontalAlignment: Text.AlignHCenter
                    readOnly: true
                    selectByKeyboard: true; selectByMouse: true

                    width: parent.width
                    anchors.top: copyLinkButton.bottom

                    onLinkActivated: Qt.openUrlExternally(link)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: parent.hoveredLink ?
                                         Qt.PointingHandCursor :
                                         Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton
                    }
                }
                Button {
                    id: redactButton

                    text: "Redact"

                    anchors.right: copyLinkButton.left
                    z: 1

                    onClicked: {
                        room.redactEvent(eventId)
                        showDetails.checked = false
                    }
                }
                Button {
                    id: copyLinkButton

                    text: "Copy link to clipboard"

                    anchors.right: parent.right
                    z: 1

                    onClicked: {
                        permalink.selectAll()
                        permalink.copy()
                        showDetails.checked = false
                    }
                }
                TextEdit {
                    id: permalink
                    text: evtLink
                    renderType: settings.render_type
                    width: 0; height: 0; visible: false
                }
            }

            TextArea {
                text: sourceText;
                textFormat: Text.PlainText
                readOnly: true;
                font.family: "Monospace"
                // FIXME: make settings.render_type an integer (but store as string to stay human-friendly)
//                style: TextAreaStyle {
//                    renderType: settings.render_type
//                }
                selectByKeyboard: true; selectByMouse: true;

                width: parent.width
                anchors.top: detailsHeader.bottom
            }
        }
    }
}
