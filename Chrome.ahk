﻿class Chrome
{
	static DebugPort := 9222
	
	; Escape a string in a manner suitable for command line parameters
	CliEscape(Param)
	{
		return """" RegExReplace(Param, "(\\*)""", "$1$1\""") """"
	}
	
	__New(ProfilePath:="", URL:="about:blank", ChromePath:="", DebugPort:="")
	{
		if (ProfilePath != "" && !InStr(FileExist(ProfilePath), "D"))
			throw Exception("The given ProfilePath does not exist")
		this.ProfilePath := ProfilePath
		
		; TODO: Perform a more rigorous search for Chrome
		if (ChromePath == "")
			FileGetShortcut, %A_StartMenuCommon%\Programs\Google Chrome.lnk, ChromePath
		if !FileExist(ChromePath)
			throw Exception("Chrome could not be found")
		this.ChromePath := ChromePath
		
		if (DebugPort != "")
		{
			this.DebugPort := Round(DebugPort)
			if (this.DebugPort <= 0) ; TODO: Support DebugPort of 0
				throw Exception("DebugPort must be a positive integer")
		}
		
		; TODO: Support an array of URLs
		Run, % this.CliEscape(ChromePath)
		. " --remote-debugging-port=" this.DebugPort
		. (ProfilePath ? " --user-data-dir=" this.CliEscape(ProfilePath) : "")
		. (URL ? " " this.CliEscape(URL) : "")
	}
	
	GetTabs()
	{
		http := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		http.open("GET", "http://127.0.0.1:" this.DebugPort "/json")
		http.send()
		return this.Jxon_Load(http.responseText)
	}
	
	GetTab(Index:=0)
	{
		; TODO: Filter pages by type before returning an indexed page
		if (Index > 0)
			return new this.Tab(this.GetTabs()[Index])
		
		for Index, Tab in this.GetTabs()
			if (Tab.type == "page")
				return new this.Tab(Tab)
	}
	
	class Tab
	{
		Connected := False
		ID := 0
		Responses := []
		
		__New(wsurl)
		{
			this.BoundKeepAlive := this.Call.Bind(this, "Browser.getVersion",, False)
			
			; TODO: Throw exception on invalid objects
			if IsObject(wsurl)
				wsurl := wsurl.webSocketDebuggerUrl
			
			wsurl := StrReplace(wsurl, "localhost", "127.0.0.1")
			this.ws := {"base": this.WebSocket, "_Event": this.Event, "Parent": this}
			this.ws.__New(wsurl)
			
			while !this.Connected
				Sleep, 50
		}
		
		Call(DomainAndMethod, Params:="", WaitForResponse:=True)
		{
			if !this.Connected
				throw Exception("Not connected to tab")
			
			; Use a temporary variable for ID in case more calls are made
			; before we receive a response.
			ID := this.ID += 1
			this.ws.Send(Chrome.Jxon_Dump({"id": ID
			, "method": DomainAndMethod, "params": Params}))
			
			if !WaitForResponse
				return
			
			; Wait for the response
			this.responses[ID] := False
			while !this.responses[ID]
				Sleep, 50
			
			; Get the response, check if it's an error
			response := this.responses.Delete(ID)
			if (response.error)
				throw Exception("Chrome indicated error in response",, Chrome.Jxon_Dump(response.error))
			
			return response.result
		}
		
		Evaluate(JS)
		{
			response := this.Call("Runtime.evaluate",
			( LTrim Join
			{
				"expression": JS,
				"objectGroup": "console",
				"includeCommandLineAPI": Chrome.Jxon_True(),
				"silent": Chrome.Jxon_False(),
				"returnByValue": Chrome.Jxon_False(),
				"userGesture": Chrome.Jxon_True(),
				"awaitPromise": Chrome.Jxon_False()
			}
			))
			
			if (response.exceptionDetails)
				throw Exception(response.result.description,, Chrome.Jxon_Dump(response.exceptionDetails))
			
			return response.result
		}
		
		WaitForLoad(DesiredState:="complete", Interval:=100)
		{
			while this.Evaluate("document.readyState").value != DesiredState
				Sleep, %Interval%
		}
		
		Event(EventName, Event)
		{
			; Called from WebSocket
			if this.Parent
				this := this.Parent
			
			; TODO: Handle Error events
			if (EventName == "Open")
			{
				this.Connected := True
				BoundKeepAlive := this.BoundKeepAlive
				SetTimer, %BoundKeepAlive%, 15000
			}
			else if (EventName == "Message")
			{
				data := Chrome.Jxon_Load(Event.data)
				if this.responses.HasKey(data.ID)
					this.responses[data.ID] := data
			}
			else if (EventName == "Close")
			{
				this.Disconnect()
			}
		}
		
		Disconnect()
		{
			if !this.Connected
				return
			
			this.Connected := False
			this.ws.Delete("Parent")
			this.ws.Disconnect()
			
			BoundKeepAlive := this.BoundKeepAlive
			SetTimer, %BoundKeepAlive%, Delete
			this.Delete("BoundKeepAlive")
		}
		
		#Include %A_LineFile%\..\lib\WebSocket.ahk\WebSocket.ahk
	}
	
	#Include %A_LineFile%\..\lib\AutoHotkey-JSON\Jxon.ahk
}
