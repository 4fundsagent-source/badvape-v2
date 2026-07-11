local cloneref = cloneref or function(ref)
	return ref
end

if isfolder('badvape') then
	delfolder('badvape')
end

cloneref(game:GetService('StarterGui')):SetCore('SendNotification', {
	Title = 'BadVape',
	Text = 'Successfully reinstalled BadVape. Rejoin the game to take effect.',
	Duration = 20,
})
