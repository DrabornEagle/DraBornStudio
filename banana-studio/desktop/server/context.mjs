let workspace;
export const LOCAL_AUTH = Symbol('native-loopback-authentication');
export function setWorkspace(value) { workspace=value; }
export function getWorkspace() { if(!workspace)throw new Error('Local workspace is not open.');return workspace; }
