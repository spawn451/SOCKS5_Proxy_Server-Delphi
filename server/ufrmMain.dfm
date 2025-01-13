object Form1: TForm1
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  Caption = 'Proxy server'
  ClientHeight = 441
  ClientWidth = 941
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object pnlToolBar: TPanel
    Left = 0
    Top = 0
    Width = 941
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object pnlPort: TPanel
      Left = 118
      Top = 0
      Width = 827
      Height = 41
      BevelOuter = bvNone
      TabOrder = 1
      object prxPort: TSpinEdit
        AlignWithMargins = True
        Left = 0
        Top = 9
        Width = 121
        Height = 24
        Margins.Left = 0
        Margins.Top = 5
        Margins.Right = 5
        Margins.Bottom = 5
        TabStop = False
        MaxValue = 0
        MinValue = 0
        TabOrder = 0
        Value = 1080
        OnChange = prxPortChange
      end
    end
    object btnActivateProxyServer: TButton
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 105
      Height = 31
      Margins.Left = 5
      Margins.Top = 5
      Margins.Right = 5
      Margins.Bottom = 5
      Align = alLeft
      Caption = 'Start Proxy Server'
      TabOrder = 0
      TabStop = False
      OnClick = btnActivateProxyServerClick
    end
  end
  object ListView1: TListView
    AlignWithMargins = True
    Left = 3
    Top = 44
    Width = 935
    Height = 329
    Align = alClient
    BevelOuter = bvNone
    BorderStyle = bsNone
    Columns = <
      item
        Caption = 'id'
        Width = 0
      end
      item
        Caption = 'Target Server'
        Width = 150
      end
      item
        Caption = 'Target Port'
        Width = 150
      end
      item
        Caption = 'Proxy Type'
        Width = 150
      end>
    ParentShowHint = False
    ShowHint = False
    TabOrder = 1
    ViewStyle = vsReport
    ExplicitLeft = 8
    ExplicitTop = 47
    ExplicitHeight = 345
  end
  object memLog: TMemo
    AlignWithMargins = True
    Left = 5
    Top = 376
    Width = 931
    Height = 60
    Margins.Left = 5
    Margins.Top = 0
    Margins.Right = 5
    Margins.Bottom = 5
    Align = alBottom
    BorderStyle = bsNone
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 2
    OnKeyDown = memLogKeyDown
  end
end
