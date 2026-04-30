import { useState, useEffect } from 'react';
import { Bell, MessageSquare, ClipboardList, AlertCircle, ArrowUpRight, Loader2, ChevronDown, ChevronUp, User, Clock } from 'lucide-react';
import { api } from '../api';

const typeConfig = {
  SMS: { icon: MessageSquare, label: 'Patient Messages', desc: 'SMS notifications sent to patients', gradient: 'from-blue-500 to-blue-600', light: 'bg-blue-50 text-blue-700 border-blue-100', iconBg: 'bg-blue-100 text-blue-600', dot: 'bg-blue-500' },
  TASK: { icon: ClipboardList, label: 'Care Team Tasks', desc: 'Follow-up actions for care managers', gradient: 'from-purple-500 to-purple-600', light: 'bg-purple-50 text-purple-700 border-purple-100', iconBg: 'bg-purple-100 text-purple-600', dot: 'bg-purple-500' },
  ALERT: { icon: AlertCircle, label: 'Pharmacy Alerts', desc: 'Medication adherence and refill alerts', gradient: 'from-red-500 to-red-600', light: 'bg-red-50 text-red-700 border-red-100', iconBg: 'bg-red-100 text-red-600', dot: 'bg-red-500' },
  REFERRAL: { icon: ArrowUpRight, label: 'Specialist Referrals', desc: 'Referrals to specialists and programs', gradient: 'from-emerald-500 to-emerald-600', light: 'bg-emerald-50 text-emerald-700 border-emerald-100', iconBg: 'bg-emerald-100 text-emerald-600', dot: 'bg-emerald-500' },
};

const priorityConfig = {
  CRITICAL: { bg: 'bg-red-100 text-red-800 border border-red-200', dot: 'bg-red-500' },
  HIGH: { bg: 'bg-orange-100 text-orange-800 border border-orange-200', dot: 'bg-orange-500' },
  MEDIUM: { bg: 'bg-yellow-100 text-yellow-800 border border-yellow-200', dot: 'bg-yellow-500' },
  LOW: { bg: 'bg-green-100 text-green-800 border border-green-200', dot: 'bg-green-500' },
};

const sectionOrder = ['SMS', 'TASK', 'ALERT', 'REFERRAL'];

function NotificationItem({ n, cfg }) {
  const [open, setOpen] = useState(false);
  const Icon = cfg.icon;
  const pCfg = priorityConfig[n.priority] || priorityConfig.MEDIUM;
  const preview = n.message?.length > 80 ? n.message.slice(0, 80) + '...' : n.message;

  return (
    <div className={`transition-colors ${n.status === 'unread' ? 'bg-white' : 'bg-gray-50/50'}`}>
      {/* Collapsed row — click to expand */}
      <button onClick={() => setOpen(!open)} className="w-full text-left px-5 py-4 flex items-center gap-4 hover:bg-gray-50/80 transition-colors">
        <div className={`w-9 h-9 rounded-xl flex items-center justify-center shrink-0 ${cfg.iconBg}`}>
          <Icon className="w-4 h-4" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold text-gray-900">{n.memberId}</span>
            <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${pCfg.bg}`}>{n.priority}</span>
            {n.status === 'unread' && <span className={`w-2 h-2 rounded-full ${cfg.dot} animate-pulse`} />}
          </div>
          {!open && <p className="text-sm text-gray-500 mt-0.5 truncate">{preview}</p>}
        </div>
        <div className="shrink-0 text-gray-400">
          {open ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
        </div>
      </button>

      {/* Expanded detail panel */}
      {open && (
        <div className="px-5 pb-5 pt-0 ml-[52px] border-l-2 border-gray-100">
          {/* Full message */}
          <div className="bg-gray-50 rounded-xl p-4 mb-3">
            <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">{n.message}</p>
          </div>

          {/* Detail grid */}
          <div className="grid grid-cols-2 gap-3 text-xs">
            <div className="bg-white border border-gray-100 rounded-lg p-3">
              <p className="text-gray-400 mb-1">Type</p>
              <p className="font-semibold text-gray-700 flex items-center gap-1"><Icon className="w-3 h-3" /> {n.type}</p>
            </div>
            <div className="bg-white border border-gray-100 rounded-lg p-3">
              <p className="text-gray-400 mb-1">Priority</p>
              <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${pCfg.bg}`}>{n.priority}</span>
            </div>
            <div className="bg-white border border-gray-100 rounded-lg p-3">
              <p className="text-gray-400 mb-1">Target</p>
              <p className="font-semibold text-gray-700 flex items-center gap-1"><User className="w-3 h-3" /> {n.target || 'N/A'}</p>
            </div>
            <div className="bg-white border border-gray-100 rounded-lg p-3">
              <p className="text-gray-400 mb-1">Status</p>
              <p className="font-semibold text-gray-700 flex items-center gap-1">
                {n.status === 'unread'
                  ? <><span className="w-2 h-2 rounded-full bg-blue-500" /> Unread</>
                  : <><span className="w-2 h-2 rounded-full bg-gray-400" /> Read</>
                }
              </p>
            </div>
            {n.createdAt && (
              <div className="col-span-2 bg-white border border-gray-100 rounded-lg p-3">
                <p className="text-gray-400 mb-1">Triggered At</p>
                <p className="font-semibold text-gray-700 flex items-center gap-1">
                  <Clock className="w-3 h-3" /> {new Date(n.createdAt).toLocaleString()}
                </p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function Section({ type, items }) {
  const [expanded, setExpanded] = useState(true);
  const cfg = typeConfig[type] || typeConfig.TASK;
  const Icon = cfg.icon;
  const unreadCount = items.filter(n => n.status === 'unread').length;

  return (
    <div className="rounded-2xl border border-gray-200 overflow-hidden shadow-sm hover:shadow-md transition-shadow">
      {/* Header */}
      <button onClick={() => setExpanded(!expanded)}
        className={`w-full bg-gradient-to-r ${cfg.gradient} px-6 py-4 flex items-center justify-between cursor-pointer`}>
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-white/20 rounded-xl flex items-center justify-center backdrop-blur-sm">
            <Icon className="w-5 h-5 text-white" />
          </div>
          <div className="text-left">
            <h3 className="font-semibold text-white text-base">{cfg.label}</h3>
            <p className="text-white/70 text-xs">{cfg.desc}</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          {unreadCount > 0 && (
            <span className="bg-white/25 text-white text-xs font-bold px-2.5 py-1 rounded-full backdrop-blur-sm">
              {unreadCount} new
            </span>
          )}
          <span className="bg-white/15 text-white text-sm font-medium px-3 py-1 rounded-full">
            {items.length}
          </span>
          {expanded ? <ChevronUp className="w-5 h-5 text-white/70" /> : <ChevronDown className="w-5 h-5 text-white/70" />}
        </div>
      </button>

      {/* Items */}
      {expanded && (
        <div className="divide-y divide-gray-100">
          {items.map((n, i) => (
            <NotificationItem key={i} n={n} cfg={cfg} />
          ))}
        </div>
      )}
    </div>
  );
}

export default function NotificationsPage() {
  const [notifications, setNotifications] = useState([]);
  const [unread, setUnread] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    
    async function loadNotifications() {
      try {
        const data = await api.notifications();
        if (!cancelled) {
          setNotifications(data.notifications || []);
          setUnread(data.unread || 0);
          setLoading(false);
        }
      } catch (err) {
        console.error('Notifications error:', err);
        if (!cancelled) setLoading(false);
      }
    }

    loadNotifications();

    // Auto-refresh every 10 seconds
    const interval = setInterval(() => {
      if (!cancelled) loadNotifications();
    }, 10000);

    return () => { cancelled = true; clearInterval(interval); };
  }, []);

  if (loading) return (
    <div className="flex items-center justify-center h-96">
      <div className="text-center">
        <Loader2 className="w-8 h-8 animate-spin text-blue-500 mx-auto mb-3" />
        <p className="text-gray-500">Loading notifications...</p>
      </div>
    </div>
  );

  const grouped = {};
  for (const n of notifications) {
    const type = n.type || 'OTHER';
    if (!grouped[type]) grouped[type] = [];
    grouped[type].push(n);
  }

  const totalCount = notifications.length;

  return (
    <div className="p-8 max-w-5xl mx-auto">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900">Notifications</h1>
        <p className="text-gray-500 mt-1">Workflow actions triggered by the AI agent</p>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-8">
        {sectionOrder.map(type => {
          const cfg = typeConfig[type];
          const Icon = cfg.icon;
          const count = (grouped[type] || []).length;
          const unreadCount = (grouped[type] || []).filter(n => n.status === 'unread').length;
          return (
            <div key={type} className={`rounded-xl border p-4 ${cfg.light}`}>
              <div className="flex items-center justify-between mb-2">
                <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${cfg.iconBg}`}>
                  <Icon className="w-4 h-4" />
                </div>
                {unreadCount > 0 && (
                  <span className={`w-5 h-5 rounded-full ${cfg.dot} text-white text-xs flex items-center justify-center font-bold`}>
                    {unreadCount}
                  </span>
                )}
              </div>
              <p className="text-2xl font-bold">{count}</p>
              <p className="text-xs opacity-70">{cfg.label}</p>
            </div>
          );
        })}
      </div>

      {/* Empty State */}
      {totalCount === 0 ? (
        <div className="text-center py-20">
          <div className="w-20 h-20 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <Bell className="w-10 h-10 text-gray-300" />
          </div>
          <p className="text-lg font-medium text-gray-500">No notifications yet</p>
          <p className="text-sm text-gray-400 mt-1">Chat with the AI agent to trigger care workflows</p>
        </div>
      ) : (
        <div className="space-y-5">
          {sectionOrder.map(type => {
            const items = grouped[type];
            if (!items || items.length === 0) return null;
            return <Section key={type} type={type} items={items} />;
          })}
        </div>
      )}
    </div>
  );
}
