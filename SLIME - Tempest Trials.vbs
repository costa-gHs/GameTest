Set objShell = CreateObject("WScript.Shell")

' Tentar encontrar Love2D
Dim lovePath
lovePath = ""

' Verificar pasta atual
If objShell.Run("cmd /c if exist love.exe echo found", 0, True) = 0 Then
    lovePath = Chr(34) & objShell.CurrentDirectory & "\love.exe" & Chr(34)
ElseIf objShell.Run("cmd /c if exist " & Chr(34) & "C:\Program Files\LOVE\love.exe" & Chr(34) & " echo found", 0, True) = 0 Then
    lovePath = Chr(34) & "C:\Program Files\LOVE\love.exe" & Chr(34)
ElseIf objShell.Run("cmd /c if exist " & Chr(34) & "C:\Program Files (x86)\LOVE\love.exe" & Chr(34) & " echo found", 0, True) = 0 Then
    lovePath = Chr(34) & "C:\Program Files (x86)\LOVE\love.exe" & Chr(34)
Else
    ' Tentar usar do PATH
    lovePath = "love"
End If

' Executar o jogo
objShell.Run lovePath & " " & Chr(34) & objShell.CurrentDirectory & Chr(34), 1, False 