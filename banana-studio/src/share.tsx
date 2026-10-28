import React from 'react';
import { initializeWorkspaceApi } from './services/workspaceApi.mjs';
import { createRoot } from 'react-dom/client';
import { SharedFolder } from './components/SharedFolder';
import './styles/sharedFolder.css';

const root = createRoot(document.getElementById('root')!);
void initializeWorkspaceApi().then(() => root.render(<React.StrictMode><SharedFolder /></React.StrictMode>)).catch(() => root.render(<p role="alert">Paylaşılan klasör sunucusu yapılandırılmamış.</p>));
