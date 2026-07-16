local cloneref = cloneref or function(ref)
	return ref
end

local folder = shared.BadVapeFolder or 'badvape'
if isfolder(folder) then
	if type(delfolder) ~= 'function' then
		error('Your executor cannot remove the existing BadVape folder.', 0)
	end
	local deleted, deleteError = pcall(delfolder, folder)
	if not deleted or isfolder(folder) then
		error('Failed to remove the existing BadVape folder: '..tostring(deleteError or 'folder still exists'), 0)
	end
end

cloneref(game:GetService('StarterGui')):SetCore('SendNotification', {
	Title = 'BadVape',
	Text = 'Successfully reinstalled BadVape. Rejoin the game to take effect.',
	Duration = 20,
})
