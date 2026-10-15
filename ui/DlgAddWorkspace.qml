import QtQuick

// "Add a workspace": the sign-in page (LoginView in its adding mode) in a
// tall card; it closes once the new workspace is in.
DialogFrame {
  id: d
  title: ""
  cardWidth: t.sp(560)

  Column {
    width: parent.width

    LoginView {
      app: d.app
      adding: true
      width: parent.width
      height: Math.max(d.t.sp(360), Math.min(d.t.sp(640), d.maxHeight - d.t.sp(90)))
      color: "transparent"
      onFinished: d.closed()
    }
  }
}
