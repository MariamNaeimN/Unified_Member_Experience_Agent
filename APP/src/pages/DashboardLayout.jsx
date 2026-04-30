import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { LayoutDashboard, MessageSquare, Users, Bell, Heart, LogOut, ChevronRight, Sparkles } from 'lucide-react';

const navItems = [
  { to: '/dashboard', icon: LayoutDashboard, label: 'Dashboard', desc: 'Member overview' },
  { to: '/chat', icon: MessageSquare, label: 'Chat Agent', desc: 'AI-powered analysis' },
  { to: '/notifications', icon: Bell, label: 'Notifications', desc: 'Workflow alerts' },
];

export default function DashboardLayout({ user, onLogout }) {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-gray-50 flex">
      {/* Sidebar */}
      <aside className="w-72 bg-gradient-to-b from-slate-900 via-slate-900 to-slate-800 flex flex-col text-white fixed top-0 left-0 h-screen overflow-y-auto z-10">
        {/* Logo */}
        <div className="px-6 py-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-gradient-to-br from-blue-400 to-blue-600 rounded-xl flex items-center justify-center shadow-lg shadow-blue-500/20">
              <Heart className="w-5 h-5 text-white" />
            </div>
            <div>
              <h1 className="font-bold text-lg tracking-tight">MemberXP</h1>
              <p className="text-[10px] text-slate-400 uppercase tracking-widest">Powered by Rackspace</p>
            </div>
          </div>
        </div>

        {/* AI Badge */}
        <div className="mx-4 mb-4 bg-gradient-to-r from-blue-600/20 to-purple-600/20 border border-blue-500/20 rounded-xl px-4 py-3">
          <div className="flex items-center gap-2 text-blue-300 text-xs font-medium">
            <Sparkles className="w-3.5 h-3.5" />
            AI Care Management
          </div>
          <p className="text-[11px] text-slate-400 mt-1">Bedrock Claude 3 Haiku</p>
        </div>

        {/* Navigation */}
        <nav className="flex-1 px-3 space-y-1">
          <p className="text-[10px] text-slate-500 uppercase tracking-widest font-semibold px-3 mb-2">Navigation</p>
          {navItems.map(({ to, icon: Icon, label, desc }) => (
            <NavLink key={to} to={to}
              className={({ isActive }) =>
                `group flex items-center gap-3 px-4 py-3 rounded-xl text-sm transition-all duration-200 ${
                  isActive
                    ? 'bg-white/10 text-white shadow-lg shadow-black/10'
                    : 'text-slate-400 hover:bg-white/5 hover:text-white'
                }`
              }>
              {({ isActive }) => (
                <>
                  <div className={`w-9 h-9 rounded-lg flex items-center justify-center transition-all ${
                    isActive ? 'bg-blue-500 shadow-md shadow-blue-500/30' : 'bg-slate-800 group-hover:bg-slate-700'
                  }`}>
                    <Icon className="w-4.5 h-4.5" />
                  </div>
                  <div className="flex-1">
                    <p className="font-medium">{label}</p>
                    <p className={`text-[11px] ${isActive ? 'text-slate-300' : 'text-slate-500'}`}>{desc}</p>
                  </div>
                  {isActive && <div className="w-1.5 h-8 bg-blue-400 rounded-full" />}
                </>
              )}
            </NavLink>
          ))}
        </nav>

        {/* User Profile */}
        <div className="p-4 border-t border-slate-700/50">
          <div
            onClick={() => navigate('/profile')}
            className="bg-slate-800/50 hover:bg-slate-700/50 rounded-xl p-3 cursor-pointer transition-all group mb-3">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-gradient-to-br from-blue-400 to-indigo-500 rounded-xl flex items-center justify-center font-bold text-sm shadow-md">
                {user.name?.[0] || 'S'}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-white truncate">{user.name}</p>
                <p className="text-[11px] text-slate-400 truncate">{user.email}</p>
              </div>
              <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition" />
            </div>
            <div className="flex items-center gap-3 mt-2 pt-2 border-t border-slate-700/50">
              <span className="flex items-center gap-1 text-[11px] text-slate-400">
                <span className="w-1.5 h-1.5 bg-green-400 rounded-full" /> Active
              </span>
              <span className="text-[11px] text-slate-500">Care Manager</span>
            </div>
          </div>

          <button onClick={onLogout}
            className="w-full flex items-center justify-center gap-2 px-3 py-2.5 text-sm text-slate-400 hover:text-red-400 hover:bg-red-500/10 rounded-xl transition-all">
            <LogOut className="w-4 h-4" /> Sign Out
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 overflow-auto ml-72">
        <Outlet />
      </main>
    </div>
  );
}
