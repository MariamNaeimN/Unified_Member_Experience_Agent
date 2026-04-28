import { useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { setToken } from './api';
import LoginPage from './pages/LoginPage';
import DashboardLayout from './pages/DashboardLayout';
import ChatPage from './pages/ChatPage';
import MembersPage from './pages/MembersPage';
import ProfilePage from './pages/ProfilePage';
import NotificationsPage from './pages/NotificationsPage';

export default function App() {
  const [user, setUser] = useState(null);

  function handleLogin(userData) {
    setToken(userData.idToken);
    setUser(userData);
  }

  if (!user) return <LoginPage onLogin={handleLogin} />;

  return (
    <BrowserRouter>
      <Routes>
        <Route element={<DashboardLayout user={user} onLogout={() => setUser(null)} />}>
          <Route path="/" element={<Navigate to="/chat" />} />
          <Route path="/chat" element={<ChatPage />} />
          <Route path="/members" element={<MembersPage />} />
          <Route path="/members/:memberId" element={<ProfilePage />} />
          <Route path="/notifications" element={<NotificationsPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
