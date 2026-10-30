import QtQuick
import QtQuick.Controls
import "../lib/Util.js" as U

// The keyboard shortcuts guide (Ctrl+/ or F1): every key this app answers
// (ui/Shortcuts.qml and the message box), grouped like Slack's, keys drawn
// as keycaps. The search finds keys, descriptions or groups, in either
// language, accents ignored. Esc clears the search, then closes.
DialogFrame {
  id: d
  title: app.tr("Keyboard shortcuts", "Atalhos de teclado")
  cardWidth: t.sp(980)
  initialFocus: query

  // keys: alternatives, each a list of keycaps; join: how alternatives read
  // ("or" by default, "/" for a pair like previous / next, "…" for a range).
  readonly property var groups: [
    { en: "Navigation", pt: "Navegação", rows: [
      { keys: [["Ctrl", "K"], ["Ctrl", "T"], ["Ctrl", "G"]], en: "Search, or jump to a conversation", pt: "Buscar, ou ir para uma conversa" },
      { keys: [["Ctrl", "F"]], en: "Search in this conversation", pt: "Buscar nesta conversa" },
      { keys: [["Alt", "↑"], ["Alt", "↓"]], join: "/", en: "Previous / next conversation", pt: "Conversa anterior / próxima" },
      { keys: [["Alt", "Shift", "↑"], ["Ctrl", "Shift", "A"]], en: "Previous unread conversation", pt: "Conversa não lida anterior" },
      { keys: [["Alt", "Shift", "↓"]], en: "Next unread conversation", pt: "Próxima conversa não lida" },
      { keys: [["Alt", "←"], ["Ctrl", "["]], en: "Back in history", pt: "Voltar no histórico" },
      { keys: [["Alt", "→"], ["Ctrl", "]"]], en: "Forward in history", pt: "Avançar no histórico" },
      { keys: [["Ctrl", "Shift", "K"]], en: "Direct messages", pt: "Mensagens diretas" },
      { keys: [["Ctrl", "Shift", "M"]], en: "Activity: mentions and reactions", pt: "Atividade: menções e reações" },
      { keys: [["Ctrl", "Shift", "S"]], en: "Later: saved messages", pt: "Depois: mensagens salvas" },
      { keys: [["Ctrl", "Shift", "T"]], en: "Threads", pt: "Conversas (threads)" },
      { keys: [["Ctrl", "Shift", "L"]], en: "Browse channels", pt: "Navegar pelos canais" },
      { keys: [["Shift", "Esc"]], en: "Mark everything as read", pt: "Marcar tudo como lido" }
    ] },
    { en: "Messages", pt: "Mensagens", rows: [
      { keys: [["Ctrl", "N"]], en: "New message", pt: "Nova mensagem" },
      { keys: [["Enter"]], en: "Send", pt: "Enviar" },
      { keys: [["Shift", "Enter"]], en: "New line (keeps a list or quote going)", pt: "Nova linha (continua a lista ou citação)" },
      { keys: [["↑"]], en: "Empty box: select messages", pt: "Caixa vazia: selecionar mensagens" },
      { keys: [["Ctrl", "↑"]], en: "Empty box: edit your last message", pt: "Caixa vazia: editar sua última mensagem" },
      { keys: [["Enter"], ["Esc"]], join: "/", en: "While editing: save / cancel", pt: "Editando: salvar / cancelar" },
      { keys: [["Esc"]], en: "Mark the conversation as read", pt: "Marcar a conversa como lida" },
      { keys: [["Ctrl", "V"]], en: "Paste, pictures too", pt: "Colar, imagens também" },
      { keys: [["Ctrl", "U"]], en: "Upload a file", pt: "Enviar um arquivo" },
      { keys: [["Ctrl", "Shift", "\\"]], en: "React to the last message", pt: "Reagir à última mensagem" },
      { keys: [[":"], ["@"], ["#"], ["/"]], join: "", en: "Emoji, mention someone, a channel, a command", pt: "Emoji, mencionar alguém, um canal, um comando" },
      { keys: [["↑"], ["↓"]], join: "/", en: "In the suggestions: move", pt: "Nas sugestões: mover" },
      { keys: [["Tab"], ["Enter"]], en: "In the suggestions: pick", pt: "Nas sugestões: escolher" },
      { keys: [["Esc"]], en: "In the suggestions: dismiss", pt: "Nas sugestões: dispensar" }
    ] },
    { en: "Selected message", pt: "Mensagem selecionada", rows: [
      { keys: [["↑"], ["↓"]], join: "/", en: "Previous / next message", pt: "Mensagem anterior / próxima" },
      { keys: [["Esc"]], en: "Back to the message box", pt: "Voltar para a caixa de mensagem" },
      { keys: [["E"]], en: "Edit (yours)", pt: "Editar (as suas)" },
      { keys: [["Delete"], ["Backspace"]], en: "Delete (yours)", pt: "Excluir (as suas)" },
      { keys: [["R"]], en: "Add a reaction", pt: "Adicionar uma reação" },
      { keys: [["T"], ["Enter"]], en: "Open or reply in thread", pt: "Abrir ou responder na conversa" },
      { keys: [["A"]], en: "Save for later", pt: "Salvar para depois" },
      { keys: [["P"]], en: "Pin or unpin", pt: "Fixar ou desafixar" },
      { keys: [["S"], ["F"]], en: "Forward", pt: "Encaminhar" },
      { keys: [["U"]], en: "Mark unread", pt: "Marcar como não lida" },
      { keys: [["M"]], en: "Remind me about this", pt: "Lembrar-me disto" },
      { keys: [["L"]], en: "Copy link", pt: "Copiar link" }
    ] },
    { en: "Formatting", pt: "Formatação", rows: [
      { keys: [["Ctrl", "B"], ["Alt", "B"]], en: "Bold", pt: "Negrito" },
      { keys: [["Ctrl", "I"]], en: "Italic", pt: "Itálico" },
      { keys: [["Ctrl", "Shift", "X"], ["Alt", "X"]], en: "Strikethrough", pt: "Riscado" },
      { keys: [["Ctrl", "Shift", "C"], ["Alt", "C"]], en: "Code", pt: "Código" },
      { keys: [["Ctrl", "Alt", "Shift", "C"]], en: "Code block", pt: "Bloco de código" },
      { keys: [["Ctrl", "Shift", "9"]], en: "Quote", pt: "Citação" },
      { keys: [["Ctrl", "Shift", "8"]], en: "Bulleted list", pt: "Lista com marcadores" },
      { keys: [["Ctrl", "Shift", "7"]], en: "Numbered list", pt: "Lista numerada" },
      { keys: [["Ctrl", "Shift", "U"]], en: "Link", pt: "Link" },
      { keys: [["Enter"]], en: "Inside a ``` code block: new line", pt: "Dentro de um bloco ``` de código: nova linha" }
    ] },
    { en: "Threads & panels", pt: "Conversas e painéis", rows: [
      { keys: [["Ctrl", "B"]], en: "In a thread: also send to the channel", pt: "Numa conversa: enviar também para o canal" },
      { keys: [["Esc"]], en: "In a thread: close it", pt: "Numa conversa: fechá-la" },
      { keys: [["Ctrl", "."]], en: "Close the right-hand panel", pt: "Fechar o painel da direita" },
      { keys: [["Ctrl", "Shift", "I"], ["Alt", "I"]], en: "Channel details, or the person's profile", pt: "Detalhes do canal ou perfil da pessoa" }
    ] },
    { en: "Workspaces", pt: "Workspaces", rows: [
      { keys: [["Ctrl", "1"], ["Ctrl", "9"]], join: "…", en: "Switch to that workspace", pt: "Ir para aquele workspace" },
      { keys: [["Ctrl", "Tab"], ["Ctrl", "PgDn"]], en: "Next workspace", pt: "Próximo workspace" },
      { keys: [["Ctrl", "Shift", "Tab"], ["Ctrl", "PgUp"]], en: "Previous workspace", pt: "Workspace anterior" }
    ] },
    { en: "App", pt: "Aplicativo", rows: [
      { keys: [["Ctrl", "/"], ["F1"]], en: "This guide", pt: "Este guia" },
      { keys: [["Ctrl", ","]], en: "Preferences", pt: "Preferências" },
      { keys: [["Ctrl", "P"]], en: "Your account menu", pt: "O menu da sua conta" },
      { keys: [["Ctrl", "Shift", "Y"]], en: "Set your status", pt: "Definir seu status" },
      { keys: [["Ctrl", "="], ["Ctrl", "-"]], join: "/", en: "Zoom in / out", pt: "Aumentar / diminuir o zoom" },
      { keys: [["Ctrl", "0"]], en: "Actual size", pt: "Tamanho normal" },
      { keys: [["Ctrl", "R"]], en: "Reload channels and people", pt: "Recarregar canais e pessoas" },
      { keys: [["Ctrl", "W"], ["Ctrl", "Q"]], en: "Hide the window", pt: "Esconder a janela" }
    ] }
  ]

  // ---------------------------------------------------------------- search
  readonly property string q: U.fold(query.text.trim())
  function keysText(row) { return row.keys.map(function(k) { return k.join("+") }).join(" ") }
  function hit(s) { return d.q === "" || U.fold(s).indexOf(d.q) >= 0 }
  readonly property var shown: {
    var out = []
    d.groups.forEach(function(g) {
      var whole = d.hit(g.en) || d.hit(g.pt)
      var rows = whole ? g.rows : g.rows.filter(function(r) { return d.hit(r.en) || d.hit(r.pt) || d.hit(d.keysText(r)) })
      if (rows.length) out.push({ en: g.en, pt: g.pt, rows: rows })
    })
    return out
  }
  readonly property int count: d.shown.reduce(function(n, g) { return n + g.rows.length }, 0)
  // Two columns when there's room: groups go to the shorter one, in order.
  readonly property int cols: body.width > d.t.sp(720) ? 2 : 1
  readonly property var columns: {
    var out = [], size = []
    for (var i = 0; i < d.cols; i++) { out.push([]); size.push(0) }
    d.shown.forEach(function(g) {
      var c = 0
      for (var j = 1; j < d.cols; j++) if (size[j] < size[c]) c = j
      out[c].push(g)
      size[c] += g.rows.length + 2
    })
    return out
  }

  // The matched part, black on yellow.
  function mark(s) {
    var esc = U.escapeHtml(s)
    if (d.q === "") return esc
    var f = U.fold(s)
    var at = f.indexOf(d.q)
    if (at < 0 || f.length !== s.length) return esc
    return U.escapeHtml(s.slice(0, at)) + "<span style=\"background-color:" + d.t.hex(d.t.yellow) + ";color:#1a1d21;\">" + U.escapeHtml(s.slice(at, at + d.q.length)) + "</span>" + U.escapeHtml(s.slice(at + d.q.length))
  }

  Column {
    id: body
    width: parent.width
    spacing: d.t.sp(12)

    Item {
      width: parent.width
      height: query.implicitHeight
      SField {
        id: query
        app: d.app
        anchors.fill: parent
        icon: "󰍉"
        rightPadding: d.t.sp(130)
        placeholderText: d.app.tr("Search keys or what they do", "Buscar teclas ou o que elas fazem")
        Keys.onPressed: event => {
          var k = event.key
          if (k === Qt.Key_Escape && query.text !== "") { query.text = ""; event.accepted = true }
          else if (k === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) { query.text = ""; event.accepted = true }
          else if (k === Qt.Key_Down) { list.flick(0, -900); event.accepted = true }
          else if (k === Qt.Key_Up) { list.flick(0, 900); event.accepted = true }
          else if (k === Qt.Key_PageDown) { list.contentY = Math.min(Math.max(0, list.contentHeight - list.height), list.contentY + list.height * 0.9); event.accepted = true }
          else if (k === Qt.Key_PageUp) { list.contentY = Math.max(0, list.contentY - list.height * 0.9); event.accepted = true }
        }
        onTextChanged: list.contentY = 0
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: d.t.sp(12)
        anchors.verticalCenter: parent.verticalCenter
        text: d.count === 1 ? d.app.tr("1 shortcut", "1 atalho") : d.count + d.app.tr(" shortcuts", " atalhos")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsSmall
      }
    }

    Flickable {
      id: list
      width: parent.width
      height: Math.max(d.t.sp(240), Math.min(d.t.sp(620), d.maxHeight - d.t.sp(170)))
      contentHeight: Math.max(colsRow.implicitHeight, empty.visible ? empty.implicitHeight : 0)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ThinScroll { app: d.app }

      Text {
        id: empty
        visible: d.count === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: d.t.sp(40)
        text: d.app.tr("No shortcuts match", "Nenhum atalho encontrado")
        color: d.t.fgDim
        font.family: d.t.font
        font.pixelSize: d.t.fsText
      }

      Row {
        id: colsRow
        width: list.width - d.t.sp(12)
        spacing: d.t.sp(36)
        Repeater {
          model: d.columns
          delegate: Column {
            id: column
            required property var modelData
            width: (colsRow.width - colsRow.spacing * (d.cols - 1)) / d.cols
            spacing: d.t.sp(18)
            Repeater {
              model: column.modelData
              delegate: Column {
                id: group
                required property var modelData
                width: column.width
                spacing: d.t.sp(2)
                Text {
                  width: parent.width
                  textFormat: Text.RichText
                  text: d.mark(d.app.tr(group.modelData.en, group.modelData.pt))
                  color: d.t.fgBright
                  font.family: d.t.font
                  font.pixelSize: d.t.fsTitle - 1
                  font.bold: true
                  bottomPadding: d.t.sp(6)
                }
                Repeater {
                  model: group.modelData.rows
                  delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: group.width
                    height: Math.max(caps.height, desc.implicitHeight) + d.t.sp(12)
                    Rectangle { visible: row.index > 0; width: parent.width; height: 1; color: d.t.line }
                    Text {
                      id: desc
                      anchors.left: parent.left
                      anchors.right: caps.left
                      anchors.rightMargin: d.t.sp(14)
                      anchors.verticalCenter: parent.verticalCenter
                      wrapMode: Text.Wrap
                      textFormat: Text.RichText
                      text: d.mark(d.app.tr(row.modelData.en, row.modelData.pt))
                      color: d.t.fg
                      font.family: d.t.font
                      font.pixelSize: d.t.fsText - 1
                    }
                    Row {
                      id: caps
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: d.t.sp(5)
                      Repeater {
                        model: row.modelData.keys
                        delegate: Row {
                          id: combo
                          required property var modelData
                          required property int index
                          spacing: d.t.sp(5)
                          Text {
                            visible: combo.index > 0 && row.modelData.join !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: { var j = row.modelData.join || "or"; return j === "or" ? d.app.tr("or", "ou") : j }
                            color: d.t.fgDim
                            font.family: d.t.font
                            font.pixelSize: d.t.fsTiny
                          }
                          Repeater {
                            model: combo.modelData
                            delegate: Rectangle {
                              required property var modelData
                              readonly property bool lit: d.q !== "" && U.fold(modelData).indexOf(d.q) >= 0 && d.q.length >= Math.min(2, modelData.length)
                              anchors.verticalCenter: parent.verticalCenter
                              width: Math.max(d.t.sp(22), cap.implicitWidth + d.t.sp(12))
                              height: d.t.sp(22)
                              radius: Math.max(4, d.t.radiusSmall)
                              color: lit ? d.t.alpha(d.t.yellow, 0.85) : d.t.alpha(d.t.fg, 0.07)
                              border.width: 1
                              border.color: lit ? d.t.yellow : d.t.lineStrong
                              Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 1
                                height: 2
                                radius: 1
                                color: d.t.alpha(d.t.bgDarker, 0.6)
                              }
                              Text {
                                id: cap
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                text: modelData
                                color: parent.lit ? "#1a1d21" : d.t.fgBright
                                font.family: d.t.font
                                font.pixelSize: d.t.fsTiny
                                font.bold: true
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
