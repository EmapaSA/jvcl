object LocalsForm: TLocalsForm
  Left = 256
  Top = 183
  Width = 220
  Height = 270
  BorderStyle = bsSizeToolWin
  Caption = 'Locals'
  Color = clBtnFace
  DockSite = True
  DragKind = dkDock
  DragMode = dmAutomatic
  Font.Charset = ANSI_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = #203#206#204#229
  Font.Style = []
  FormStyle = fsStayOnTop
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 15
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 212
    Height = 243
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object ComboBoxPanel: TPanel
      Left = 0
      Top = 0
      Width = 212
      Height = 30
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      OnResize = ComboBoxPanelResize
      object ComboBox: TComboBox
        Left = 0
        Top = 1
        Width = 212
        Height = 23
        ItemHeight = 15
        TabOrder = 0
      end
    end
    object Panel: TPanel
      Left = 0
      Top = 50
      Width = 212
      Height = 193
      Align = alClient
      BevelInner = bvRaised
      BevelOuter = bvLowered
      Caption = 'Panel'
      TabOrder = 1
      object ListBox1: TListBox
        Left = 2
        Top = 2
        Width = 208
        Height = 189
        Align = alClient
        BorderStyle = bsNone
        ItemHeight = 15
        TabOrder = 0
      end
    end
    object Header: THeader
      Left = 0
      Top = 30
      Width = 212
      Height = 20
      Align = alTop
      BorderStyle = bsNone
      Sections.Sections = (
        #0'79'#0'Name'
        #0'92'#0'Value'
        #0'32'#0'Type')
      TabOrder = 2
    end
  end
  object lbDockClient1: TJvDockClient
    LRDockWidth = 100
    TBDockHeight = 100
    DirectDrag = False
    ShowHint = True
    EnableCloseButton = True
    Left = 64
    Top = 88
  end
end
