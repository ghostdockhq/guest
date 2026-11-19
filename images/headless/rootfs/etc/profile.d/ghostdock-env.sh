# The VM's environment variables for login shells (SSH, sudo -i, su - ghost),
# written by gdo-guest at every config push. Readable by root and
# the ghost group.
if [ -r /run/ghostdock/shell.env ]; then
	. /run/ghostdock/shell.env
fi
