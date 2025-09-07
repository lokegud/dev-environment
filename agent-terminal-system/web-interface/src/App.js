import React, { useState, useEffect } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import styled, { ThemeProvider, createGlobalStyle } from 'styled-components';

import Header from './components/Header';
import Sidebar from './components/Sidebar';
import TerminalView from './components/TerminalView';
import LogsView from './components/LogsView';
import DashboardView from './components/DashboardView';
import SettingsView from './components/SettingsView';
import LoginForm from './components/LoginForm';

import { AuthProvider, useAuth } from './context/AuthContext';
import { TerminalProvider } from './context/TerminalContext';
import { WebSocketProvider } from './context/WebSocketContext';

// Themes
const themes = {
  dark: {
    primary: '#0d1117',
    secondary: '#21262d',
    tertiary: '#30363d',
    accent: '#58a6ff',
    text: '#f0f6fc',
    textSecondary: '#8b949e',
    border: '#21262d',
    success: '#238636',
    warning: '#f85149',
    error: '#da3633'
  },
  matrix: {
    primary: '#000000',
    secondary: '#001100',
    tertiary: '#002200',
    accent: '#00ff00',
    text: '#00ff00',
    textSecondary: '#008800',
    border: '#003300',
    success: '#00ff00',
    warning: '#ffff00',
    error: '#ff0000'
  },
  terminal: {
    primary: '#1a1a1a',
    secondary: '#2d2d2d',
    tertiary: '#404040',
    accent: '#ffffff',
    text: '#ffffff',
    textSecondary: '#cccccc',
    border: '#555555',
    success: '#00ff00',
    warning: '#ffaa00',
    error: '#ff5555'
  }
};

const GlobalStyle = createGlobalStyle`
  * {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
  }

  body {
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    background: ${props => props.theme.primary};
    color: ${props => props.theme.text};
    overflow: hidden;
  }

  ::-webkit-scrollbar {
    width: 8px;
  }

  ::-webkit-scrollbar-track {
    background: ${props => props.theme.secondary};
  }

  ::-webkit-scrollbar-thumb {
    background: ${props => props.theme.tertiary};
    border-radius: 4px;
  }

  ::-webkit-scrollbar-thumb:hover {
    background: ${props => props.theme.accent};
  }
`;

const AppContainer = styled.div`
  height: 100vh;
  width: 100vw;
  display: flex;
  flex-direction: column;
  background: ${props => props.theme.primary};
`;

const MainContent = styled.div`
  flex: 1;
  display: flex;
  overflow: hidden;
`;

const ContentArea = styled.div`
  flex: 1;
  overflow: hidden;
  background: ${props => props.theme.primary};
`;

function AppContent() {
  const { isAuthenticated, user } = useAuth();
  const [currentTheme, setCurrentTheme] = useState('dark');
  const [sidebarOpen, setSidebarOpen] = useState(true);

  useEffect(() => {
    // Load theme from localStorage
    const savedTheme = localStorage.getItem('terminal-theme');
    if (savedTheme && themes[savedTheme]) {
      setCurrentTheme(savedTheme);
    }
  }, []);

  const handleThemeChange = (themeName) => {
    setCurrentTheme(themeName);
    localStorage.setItem('terminal-theme', themeName);
  };

  if (!isAuthenticated) {
    return (
      <ThemeProvider theme={themes[currentTheme]}>
        <GlobalStyle />
        <AppContainer>
          <LoginForm onThemeChange={handleThemeChange} currentTheme={currentTheme} />
        </AppContainer>
      </ThemeProvider>
    );
  }

  return (
    <ThemeProvider theme={themes[currentTheme]}>
      <GlobalStyle />
      <TerminalProvider>
        <WebSocketProvider>
          <AppContainer>
            <Header 
              user={user}
              onToggleSidebar={() => setSidebarOpen(!sidebarOpen)}
              sidebarOpen={sidebarOpen}
            />
            <MainContent>
              {sidebarOpen && (
                <Sidebar 
                  onThemeChange={handleThemeChange}
                  currentTheme={currentTheme}
                  themes={themes}
                />
              )}
              <ContentArea>
                <Routes>
                  <Route path="/" element={<Navigate to="/dashboard" replace />} />
                  <Route path="/dashboard" element={<DashboardView />} />
                  <Route path="/terminal" element={<TerminalView />} />
                  <Route path="/terminal/:terminalId" element={<TerminalView />} />
                  <Route path="/logs" element={<LogsView />} />
                  <Route path="/logs/:agentId" element={<LogsView />} />
                  <Route path="/settings" element={<SettingsView onThemeChange={handleThemeChange} currentTheme={currentTheme} />} />
                </Routes>
              </ContentArea>
            </MainContent>
          </AppContainer>
        </WebSocketProvider>
      </TerminalProvider>
    </ThemeProvider>
  );
}

function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}

export default App;