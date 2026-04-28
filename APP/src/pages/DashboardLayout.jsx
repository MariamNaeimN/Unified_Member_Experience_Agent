import { NavLink, Outlet } from 'react-router-dom';
import { MessageSquare, Users, Bell, Heart, LogOut } from 'lucide-react';

const navItems = [
  { to: '/chat', icon: MessageSquare, label: 'Chat Agent' },
  { to: '/members', icon: Users, label: 'Members' },
  { to: '/notifications', icon: Bell, label: 'Notifications' },
];

export default function DashboardLayout({ user, onLogout }) {
  return (
    <div className="min-h-screen bg-gray-50 flex">
      <aside className="w-64 bg-white border-r border-gray-200 flex flex-col">
        <div className="p-5 border-b border-gray-100">
          <div className="flex items-center gap-2 text-blue-600">
            <Heart className="w-6 h-6" />
            <span className="font-bold text-lg">MemberXP</span>
          </div>
          <p className="text-xs text-gray-400 mt-1">AI Care Management</p>
        </div>
        <nav className="flex-1 p-3 space-y-1">
          {navItems.map(({ to, icon: Icon, label }) => (
            <NavLink key={to} to={to}
              className={({ isActive }) =>
                `flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium transition ${
                  isActive ? 'bg-blue-50 text-blue-700' : 'text-gray-600 hover:bg-gray-50'
                }`
              }>
              <Icon className="w-5 h-5" />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="p-4 border-t border-gray-100">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-semibold text-sm">
              {user.name?.[0] || 'S'}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 truncate">{user.name}</p>
              <p className="text-xs text-gray-400 truncate">{user.email}</p>
            </div>
            <button onClick={onLogout} className="text-gray-400 hover:text-red-500 transition">
              <LogOut className="w-4 h-4" />
            </button>
          </div>
        </div>
      </aside>
      <main className="flex-1 overflow-auto">
        <Outlet />
      </main>
    </div>
  );
}
