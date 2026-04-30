import { useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { setToken, connectWebSocket, closeWebSocket } from './api';
import LoginPage from './pages/LoginPage';
import DashboardLayout from './pages/DashboardLayout';
import DashboardPage from './pages/DashboardPage';
import ChatPage from './pages/ChatPage';
import MembersPage from './pages/MembersPage';
import ProfilePage from './pages/ProfilePage';
import NotificationsPage from './pages/NotificationsPage';
import UserProfilePage from './pages/UserProfilePage';

export default function App() {
  const [user, setUser] = useState(null);

  async function handleLogin(userData) {
    setToken(userData.idToken);
    try {
      await connectWebSocket(userData.idToken);
    } catch (err) {
      console.error('WebSocket connection failed:', err);
      // Still allow login — pages will show connection errors as needed
    }
    setUser(userData);
  }

  function handleLogout() {
    closeWebSocket();
    setToken(null);
    setUser(null);
  }

  if (!user) return <LoginPage onLogin={handleLogin} />;

  return (
    <BrowserRouter>
      <Routes>
        <Route element={<DashboardLayout user={user} onLogout={handleLogout} />}>
          <Route path="/" element={<Navigate to="/dashboard" />} />
          <Route path="/dashboard" element={<DashboardPage />} />
          <Route path="/chat" element={<ChatPage />} />
          <Route path="/members" element={<MembersPage />} />
          <Route path="/members/:memberId" element={<ProfilePage />} />
          <Route path="/notifications" element={<NotificationsPage />} />
          <Route path="/profile" element={<UserProfilePage user={user} />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
