import React, { createContext, useContext, useReducer, useEffect } from 'react';
import axios from 'axios';

// Auth context
const AuthContext = createContext();

// Auth state reducer
const authReducer = (state, action) => {
  switch (action.type) {
    case 'LOGIN_START':
      return {
        ...state,
        loading: true,
        error: null
      };
    case 'LOGIN_SUCCESS':
      return {
        ...state,
        isAuthenticated: true,
        user: action.payload.user,
        token: action.payload.token,
        loading: false,
        error: null
      };
    case 'LOGIN_FAILURE':
      return {
        ...state,
        isAuthenticated: false,
        user: null,
        token: null,
        loading: false,
        error: action.payload
      };
    case 'LOGOUT':
      return {
        ...state,
        isAuthenticated: false,
        user: null,
        token: null,
        loading: false,
        error: null
      };
    case 'CLEAR_ERROR':
      return {
        ...state,
        error: null
      };
    default:
      return state;
  }
};

// Initial state
const initialState = {
  isAuthenticated: false,
  user: null,
  token: null,
  loading: false,
  error: null
};

// Auth provider component
export function AuthProvider({ children }) {
  const [state, dispatch] = useReducer(authReducer, initialState);

  // Check for existing auth token on mount
  useEffect(() => {
    const token = localStorage.getItem('terminal_auth_token');
    const user = localStorage.getItem('terminal_user');
    
    if (token && user) {
      try {
        const userData = JSON.parse(user);
        
        // Set axios default header
        axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
        
        dispatch({
          type: 'LOGIN_SUCCESS',
          payload: {
            user: userData,
            token: token
          }
        });
      } catch (error) {
        // Invalid stored data, clear it
        localStorage.removeItem('terminal_auth_token');
        localStorage.removeItem('terminal_user');
      }
    }
  }, []);

  // Login function
  const login = async (credentials) => {
    dispatch({ type: 'LOGIN_START' });
    
    try {
      // For demo purposes, we'll create a mock authentication
      // In production, this would call your actual auth API
      if (credentials.agentId && credentials.agentName) {
        const mockUser = {
          id: credentials.agentId,
          name: credentials.agentName,
          email: `${credentials.agentId}@agent-terminal.local`,
          role: 'agent'
        };
        
        // Generate a mock JWT token (in production, this comes from the server)
        const mockToken = btoa(JSON.stringify({
          agentId: credentials.agentId,
          name: credentials.agentName,
          exp: Date.now() + 24 * 60 * 60 * 1000 // 24 hours
        }));
        
        // Store in localStorage
        localStorage.setItem('terminal_auth_token', mockToken);
        localStorage.setItem('terminal_user', JSON.stringify(mockUser));
        
        // Set axios default header
        axios.defaults.headers.common['Authorization'] = `Bearer ${mockToken}`;
        
        dispatch({
          type: 'LOGIN_SUCCESS',
          payload: {
            user: mockUser,
            token: mockToken
          }
        });
        
        return { success: true };
      } else {
        throw new Error('Agent ID and name are required');
      }
    } catch (error) {
      dispatch({
        type: 'LOGIN_FAILURE',
        payload: error.response?.data?.message || error.message || 'Login failed'
      });
      
      return { success: false, error: error.message };
    }
  };

  // Logout function
  const logout = () => {
    localStorage.removeItem('terminal_auth_token');
    localStorage.removeItem('terminal_user');
    
    // Remove axios default header
    delete axios.defaults.headers.common['Authorization'];
    
    dispatch({ type: 'LOGOUT' });
  };

  // Clear error function
  const clearError = () => {
    dispatch({ type: 'CLEAR_ERROR' });
  };

  // Update user profile
  const updateProfile = async (profileData) => {
    try {
      // In production, this would call your API
      const updatedUser = { ...state.user, ...profileData };
      
      localStorage.setItem('terminal_user', JSON.stringify(updatedUser));
      
      dispatch({
        type: 'LOGIN_SUCCESS',
        payload: {
          user: updatedUser,
          token: state.token
        }
      });
      
      return { success: true };
    } catch (error) {
      return { success: false, error: error.message };
    }
  };

  // Check if token is expired
  const isTokenExpired = () => {
    if (!state.token) return true;
    
    try {
      const payload = JSON.parse(atob(state.token));
      return Date.now() > payload.exp;
    } catch {
      return true;
    }
  };

  // Auto-logout on token expiration
  useEffect(() => {
    if (state.isAuthenticated && isTokenExpired()) {
      logout();
    }
  }, [state.isAuthenticated, state.token]);

  const value = {
    ...state,
    login,
    logout,
    clearError,
    updateProfile,
    isTokenExpired
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

// Hook to use auth context
export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}