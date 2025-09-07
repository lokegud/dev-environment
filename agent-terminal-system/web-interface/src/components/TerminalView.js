import React, { useEffect, useRef, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import styled from 'styled-components';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';
import { AttachAddon } from '@xterm/addon-attach';
import '@xterm/xterm/css/xterm.css';

import { useTerminal } from '../context/TerminalContext';
import { useWebSocket } from '../context/WebSocketContext';
import { useAuth } from '../context/AuthContext';

const TerminalContainer = styled.div`
  height: 100%;
  width: 100%;
  display: flex;
  flex-direction: column;
  background: ${props => props.theme.primary};
`;

const TerminalHeader = styled.div`
  height: 40px;
  background: ${props => props.theme.secondary};
  border-bottom: 1px solid ${props => props.theme.border};
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 16px;
`;

const TerminalInfo = styled.div`
  display: flex;
  align-items: center;
  gap: 16px;
  font-size: 12px;
  color: ${props => props.theme.textSecondary};
`;

const TerminalControls = styled.div`
  display: flex;
  gap: 8px;
`;

const ControlButton = styled.button`
  background: ${props => props.theme.tertiary};
  border: 1px solid ${props => props.theme.border};
  color: ${props => props.theme.text};
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 11px;
  cursor: pointer;
  
  &:hover {
    background: ${props => props.theme.accent};
  }
  
  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
`;

const TerminalWrapper = styled.div`
  flex: 1;
  padding: 8px;
  background: ${props => props.theme.primary};
`;

const StatusIndicator = styled.div`
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: ${props => props.connected ? props.theme.success : props.theme.error};
  margin-right: 8px;
`;

const LoadingOverlay = styled.div`
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.8);
  display: flex;
  align-items: center;
  justify-content: center;
  color: ${props => props.theme.text};
  font-size: 16px;
`;

function TerminalView() {
  const { terminalId } = useParams();
  const navigate = useNavigate();
  const terminalRef = useRef();
  const { user, token } = useAuth();
  const { 
    terminals, 
    activeTerminal, 
    createTerminal, 
    destroyTerminal, 
    setActiveTerminal,
    isLoading 
  } = useTerminal();
  const { socket, isConnected } = useWebSocket();
  
  const [terminal, setTerminal] = useState(null);
  const [fitAddon, setFitAddon] = useState(null);
  const [currentTerminal, setCurrentTerminal] = useState(null);
  const [isTerminalConnected, setIsTerminalConnected] = useState(false);

  // Initialize xterm.js terminal
  useEffect(() => {
    const term = new Terminal({
      theme: {
        background: '#1a1a1a',
        foreground: '#ffffff',
        cursor: '#ffffff',
        cursorAccent: '#000000',
        selection: 'rgba(255, 255, 255, 0.3)'
      },
      fontFamily: '"Monaco", "Menlo", "Ubuntu Mono", monospace',
      fontSize: 14,
      fontWeight: 400,
      lineHeight: 1.2,
      cursorBlink: true,
      cursorStyle: 'block',
      scrollback: 10000,
      tabStopWidth: 4
    });

    const fit = new FitAddon();
    const webLinks = new WebLinksAddon();
    
    term.loadAddon(fit);
    term.loadAddon(webLinks);
    
    if (terminalRef.current) {
      term.open(terminalRef.current);
      fit.fit();
    }

    setTerminal(term);
    setFitAddon(fit);

    return () => {
      term.dispose();
    };
  }, []);

  // Find or create terminal
  useEffect(() => {
    if (!terminal || !user) return;

    const handleTerminalSetup = async () => {
      let targetTerminal = null;

      if (terminalId) {
        // Look for existing terminal
        targetTerminal = terminals.find(t => t.terminalId === terminalId);
        if (!targetTerminal) {
          navigate('/terminal');
          return;
        }
      } else if (terminals.length > 0) {
        // Use first available terminal
        targetTerminal = terminals[0];
        navigate(`/terminal/${targetTerminal.terminalId}`);
        return;
      } else {
        // Create new terminal
        try {
          targetTerminal = await createTerminal({
            agentName: user.name,
            theme: 'dark',
            enableRecording: true
          });
          navigate(`/terminal/${targetTerminal.terminalId}`);
          return;
        } catch (error) {
          console.error('Failed to create terminal:', error);
          terminal.write('\r\n\x1b[31mFailed to create terminal\x1b[0m\r\n');
          return;
        }
      }

      setCurrentTerminal(targetTerminal);
      setActiveTerminal(targetTerminal.terminalId);
    };

    handleTerminalSetup();
  }, [terminal, terminalId, terminals, user, navigate, createTerminal, setActiveTerminal]);

  // Connect to terminal WebSocket
  useEffect(() => {
    if (!socket || !terminal || !currentTerminal || !token) return;

    const connectToTerminal = () => {
      socket.emit('terminal:connect', {
        terminalId: currentTerminal.terminalId,
        token: token
      });

      socket.on('terminal:output', (data) => {
        terminal.write(data);
      });

      socket.on('terminal:connected', () => {
        setIsTerminalConnected(true);
        terminal.write('\r\n\x1b[32mTerminal connected\x1b[0m\r\n');
      });

      socket.on('terminal:error', (error) => {
        setIsTerminalConnected(false);
        terminal.write(`\r\n\x1b[31mTerminal error: ${error.message}\x1b[0m\r\n`);
      });

      // Handle terminal input
      const disposable = terminal.onData((data) => {
        if (isTerminalConnected) {
          socket.emit('terminal:input', data);
        }
      });

      // Handle terminal resize
      const resizeDisposable = terminal.onResize(({ cols, rows }) => {
        if (isTerminalConnected) {
          socket.emit('terminal:resize', { cols, rows });
        }
      });

      return () => {
        disposable.dispose();
        resizeDisposable.dispose();
        socket.off('terminal:output');
        socket.off('terminal:connected');
        socket.off('terminal:error');
      };
    };

    const cleanup = connectToTerminal();

    return cleanup;
  }, [socket, terminal, currentTerminal, token, isTerminalConnected]);

  // Handle window resize
  useEffect(() => {
    if (!fitAddon) return;

    const handleResize = () => {
      fitAddon.fit();
    };

    window.addEventListener('resize', handleResize);
    
    // Initial fit
    const timer = setTimeout(() => fitAddon.fit(), 100);

    return () => {
      window.removeEventListener('resize', handleResize);
      clearTimeout(timer);
    };
  }, [fitAddon]);

  const handleNewTerminal = async () => {
    try {
      const newTerminal = await createTerminal({
        agentName: user.name,
        theme: 'dark',
        enableRecording: true
      });
      navigate(`/terminal/${newTerminal.terminalId}`);
    } catch (error) {
      console.error('Failed to create new terminal:', error);
    }
  };

  const handleDestroyTerminal = async () => {
    if (!currentTerminal) return;
    
    if (window.confirm('Are you sure you want to destroy this terminal? All unsaved work will be lost.')) {
      try {
        await destroyTerminal(currentTerminal.terminalId);
        navigate('/terminal');
      } catch (error) {
        console.error('Failed to destroy terminal:', error);
      }
    }
  };

  const handleClear = () => {
    if (terminal) {
      terminal.clear();
    }
  };

  const handleFit = () => {
    if (fitAddon) {
      fitAddon.fit();
    }
  };

  return (
    <TerminalContainer>
      <TerminalHeader>
        <TerminalInfo>
          <StatusIndicator connected={isConnected && isTerminalConnected} />
          <span>Agent: {user?.name}</span>
          {currentTerminal && (
            <>
              <span>|</span>
              <span>Terminal: {currentTerminal.terminalId.slice(0, 8)}...</span>
              <span>|</span>
              <span>Container: {currentTerminal.containerName}</span>
            </>
          )}
        </TerminalInfo>
        <TerminalControls>
          <ControlButton onClick={handleClear}>Clear</ControlButton>
          <ControlButton onClick={handleFit}>Fit</ControlButton>
          <ControlButton onClick={handleNewTerminal} disabled={isLoading}>
            New Terminal
          </ControlButton>
          <ControlButton 
            onClick={handleDestroyTerminal} 
            disabled={!currentTerminal || isLoading}
          >
            Destroy
          </ControlButton>
        </TerminalControls>
      </TerminalHeader>
      
      <TerminalWrapper>
        <div ref={terminalRef} style={{ height: '100%', width: '100%' }} />
        {isLoading && (
          <LoadingOverlay>
            Creating terminal...
          </LoadingOverlay>
        )}
      </TerminalWrapper>
    </TerminalContainer>
  );
}

export default TerminalView;