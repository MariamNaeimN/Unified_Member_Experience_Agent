import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  LayoutDashboard, ArrowUpDown, Search, AlertTriangle, Target, Zap,
  Clock, Users, Filter, RefreshCw, Loader2, ChevronUp, ChevronDown, Wifi
} from 'lucide-react';
import { api, getWebSocket, onChatMessage } from '../api';

/* ── Helper Functions ──────────────────────────────────────────────── */

export function extractCareGapsCount(profile) {
  if (!profile || profile.error) return 0;
  const directGaps = profile.careGaps?.length || 0;
  const sessions = profile.aiDecisions || [];
  const sorted = [...sessions].sort((a, b) =>
    (b.updatedAt || '').localeCompare(a.updatedAt || '')
  );
  const sessionGaps = sorted[0]?.careGaps?.length || 0;
  return Math.max(directGaps, sessionGaps);
}

export function extractInterventionsCount(profile) {
  if (!profile || profile.error) return 0;
  const directInterventions = profile.interventions?.length || 0;
  const sessions = profile.aiDecisions || [];
  const sorted = [...sessions].sort((a, b) =>
    (b.updatedAt || '').localeCompare(a.updatedAt || '')
  );
  const sessionInterventions = sorted[0]?.interventions?.length || 0;
  return Math.max(directInterventions, sessionInterventions);
}

export function extractLastAnalysisDate(profile) {
  if (!profile || profile.error) return null;
  const sessions = profile.aiDecisions || [];
  if (sessions.length === 0) return null;
  const sorted = [...sessions].sort((a, b) =>
    (b.updatedAt || '').localeCompare(a.updatedAt || '')
  );
  return sorted[0]?.updatedAt || null;
}

export function getRiskScoreColor(score) {
  if (score == null) return 'gray';
  if (score >= 80) return 'red';
  if (score >= 50) return 'yellow';
  return 'green';
}

export function applySortAndFilter(members, profiles, { sortField, sortDirection, filterRiskMin, filterAgeMax, filterText, filterGender }) {
  // Step 1: Build enriched member list
  let enriched = members.map(m => {
    const profile = profiles[m.memberId];
    const memberData = profile?.member || {};
    // Calculate age from DOB
    let age = null;
    const dob = memberData.dob || m.dob;
    if (dob) {
      try {
        const born = new Date(dob);
        const today = new Date();
        age = today.getFullYear() - born.getFullYear() - ((today.getMonth() < born.getMonth() || (today.getMonth() === born.getMonth() && today.getDate() < born.getDate())) ? 1 : 0);
      } catch (e) {}
    }
    return {
      ...m,
      gender: memberData.gender || m.gender || '',
      riskScore: profile?.patient?.riskScore ? parseInt(profile.patient.riskScore) : null,
      careGapsCount: extractCareGapsCount(profile),
      interventionsCount: extractInterventionsCount(profile),
      lastAnalysisDate: extractLastAnalysisDate(profile),
      age,
      profile,
      profileLoaded: !!profile && !profile.error,
      profileError: profile?.error || false,
    };
  });

  // Step 2: Apply text filter (name or memberId)
  if (filterText.trim()) {
    const search = filterText.toLowerCase();
    enriched = enriched.filter(m =>
      m.memberId.toLowerCase().includes(search) ||
      `${m.firstName} ${m.lastName}`.toLowerCase().includes(search)
    );
  }

  // Step 3: Apply age range filter
  if (filterRiskMin > 0) {
    enriched = enriched.filter(m => (m.age ?? 0) >= filterRiskMin);
  }
  if (filterAgeMax > 0) {
    enriched = enriched.filter(m => (m.age ?? 999) <= filterAgeMax);
  }

  // Step 3b: Apply gender filter
  if (filterGender) {
    enriched = enriched.filter(m => m.gender === filterGender);
  }

  // Step 4: Sort with stable sort (preserve original index for ties)
  const indexed = enriched.map((item, idx) => ({ item, idx }));
  indexed.sort((a, b) => {
    let aVal = a.item[sortField];
    let bVal = b.item[sortField];

    // Handle nulls — push to end
    if (aVal == null && bVal == null) return a.idx - b.idx;
    if (aVal == null) return 1;
    if (bVal == null) return -1;

    // String comparison for name fields
    if (typeof aVal === 'string' && typeof bVal === 'string') {
      const cmp = aVal.localeCompare(bVal);
      if (cmp !== 0) return sortDirection === 'asc' ? cmp : -cmp;
      return a.idx - b.idx;
    }

    // Numeric comparison
    const diff = aVal - bVal;
    if (diff !== 0) return sortDirection === 'asc' ? diff : -diff;
    return a.idx - b.idx;
  });

  return indexed.map(({ item }) => item);
}

/* ── Data Fetching ─────────────────────────────────────────────────── */

async function fetchDashboardData(setMembers, setProfiles, setLoading, setError) {
  if (typeof setLoading === 'function') setLoading(true);
  if (typeof setError === 'function') setError(null);

  // Check WebSocket connection
  const ws = getWebSocket();
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    if (typeof setError === 'function') setError('WebSocket not connected. Please check your connection.');
    if (typeof setLoading === 'function') setLoading(false);
    return;
  }

  try {
    const membersResponse = await api.getAllMembers();
    const memberList = membersResponse.members || [];
    setMembers(memberList);

    // Fetch profiles in batches of 5
    const BATCH_SIZE = 5;
    const profileMap = {};

    for (let i = 0; i < memberList.length; i += BATCH_SIZE) {
      const batch = memberList.slice(i, i + BATCH_SIZE);
      const results = await Promise.allSettled(
        batch.map(m => api.memberProfile(m.memberId))
      );

      results.forEach((result, idx) => {
        const memberId = batch[idx].memberId;
        if (result.status === 'fulfilled') {
          profileMap[memberId] = result.value;
        } else {
          profileMap[memberId] = { error: true, errorMsg: result.reason?.message || 'Failed to load' };
        }
      });

      // Update state progressively
      setProfiles(prev => ({ ...prev, ...profileMap }));
    }
  } catch (err) {
    if (typeof setError === 'function') setError(err.message || 'Failed to fetch members');
  }

  if (typeof setLoading === 'function') setLoading(false);
}

/* ── MemberSummaryCard ─────────────────────────────────────────────── */

function MemberSummaryCard({ member, profile, profileLoading, onRetry }) {
  const navigate = useNavigate();

  const riskScore = profile?.patient?.riskScore ? parseInt(profile.patient.riskScore) : null;
  const riskColor = getRiskScoreColor(riskScore);
  const careGaps = extractCareGapsCount(profile);
  const interventions = extractInterventionsCount(profile);
  const lastAnalysis = extractLastAnalysisDate(profile);
  const hasError = profile?.error;

  const riskColorClasses = {
    red: 'text-red-600 bg-red-50 border-red-200',
    yellow: 'text-yellow-600 bg-yellow-50 border-yellow-200',
    green: 'text-green-600 bg-green-50 border-green-200',
    gray: 'text-gray-400 bg-gray-50 border-gray-200',
  };

  return (
    <div
      onClick={() => navigate(`/members/${member.memberId}`)}
      className="bg-white border border-gray-200 rounded-xl p-5 hover:shadow-lg hover:border-blue-200 transition-all cursor-pointer group"
    >
      {/* Header */}
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-sm shrink-0">
            {member.firstName?.[0]}{member.lastName?.[0]}
          </div>
          <div>
            <p className="font-semibold text-gray-900 group-hover:text-blue-600 transition-colors">
              {member.firstName} {member.lastName}
            </p>
            <p className="text-xs text-gray-500">{member.memberId} · {member.planName}</p>
          </div>
        </div>

        {/* Risk Score Badge */}
        {profileLoading ? (
          <div className="w-12 h-12 bg-gray-100 rounded-lg animate-pulse" />
        ) : (
          <div className={`w-12 h-12 rounded-lg border flex flex-col items-center justify-center ${riskColorClasses[riskColor]}`}>
            <span className="text-lg font-bold leading-none">{riskScore ?? '—'}</span>
            <span className="text-[9px] opacity-70">risk</span>
          </div>
        )}
      </div>

      {/* Metrics */}
      {profileLoading ? (
        <div className="space-y-2 mt-4">
          <div className="h-4 bg-gray-100 rounded animate-pulse w-3/4" />
          <div className="h-4 bg-gray-100 rounded animate-pulse w-1/2" />
          <div className="h-4 bg-gray-100 rounded animate-pulse w-2/3" />
        </div>
      ) : hasError ? (
        <div className="mt-4 flex items-center justify-between">
          <div className="flex items-center gap-2 text-sm text-gray-400">
            <AlertTriangle className="w-4 h-4 text-orange-400" />
            <span>Analysis unavailable</span>
          </div>
          <button
            onClick={(e) => { e.stopPropagation(); onRetry?.(member.memberId); }}
            className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-400 hover:text-blue-600 transition"
            title="Retry loading profile"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-3 gap-2 mt-4">
          <div className="text-center bg-gray-50 rounded-lg py-2">
            <div className="flex items-center justify-center gap-1 text-purple-600">
              <Target className="w-3 h-3" />
              <span className="text-sm font-bold">{careGaps}</span>
            </div>
            <p className="text-[10px] text-gray-500 mt-0.5">Care Gaps</p>
          </div>
          <div className="text-center bg-gray-50 rounded-lg py-2">
            <div className="flex items-center justify-center gap-1 text-blue-600">
              <Zap className="w-3 h-3" />
              <span className="text-sm font-bold">{interventions}</span>
            </div>
            <p className="text-[10px] text-gray-500 mt-0.5">Interventions</p>
          </div>
          <div className="text-center bg-gray-50 rounded-lg py-2">
            <div className="flex items-center justify-center gap-1 text-gray-600">
              <Clock className="w-3 h-3" />
              <span className="text-[10px] font-medium">
                {lastAnalysis ? new Date(lastAnalysis).toLocaleDateString() : '—'}
              </span>
            </div>
            <p className="text-[10px] text-gray-500 mt-0.5">Last Analysis</p>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── FilterBar ─────────────────────────────────────────────────────── */

const SORT_OPTIONS = [
  { value: 'riskScore', label: 'Risk Score' },
  { value: 'careGapsCount', label: 'Care Gaps' },
  { value: 'interventionsCount', label: 'Interventions' },
  { value: 'lastAnalysisDate', label: 'Last Analysis' },
];

function FilterBar({
  sortField, sortDirection, onSortChange,
  filterRiskMin, onFilterRiskChange,
  filterAgeMax, onFilterAgeMaxChange,
  filterText, onFilterTextChange,
  filterGender, onFilterGenderChange,
  totalCount, filteredCount
}) {
  return (
    <div className="bg-white border border-gray-200 rounded-xl p-4">
      <div className="flex flex-wrap items-center gap-4">
        {/* Sort */}
        <div className="flex items-center gap-2">
          <ArrowUpDown className="w-4 h-4 text-gray-400" />
          <select
            value={sortField}
            onChange={(e) => onSortChange(e.target.value, sortDirection)}
            className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 bg-white focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          >
            {SORT_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
          <button
            onClick={() => onSortChange(sortField, sortDirection === 'asc' ? 'desc' : 'asc')}
            className="p-1.5 rounded-lg hover:bg-gray-100 transition text-gray-500"
            title={`Sort ${sortDirection === 'asc' ? 'descending' : 'ascending'}`}
          >
            {sortDirection === 'asc' ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
          </button>
        </div>

        {/* Age Range Filter */}
        <div className="flex items-center gap-1.5">
          <Filter className="w-4 h-4 text-gray-400" />
          <span className="text-xs text-gray-500">Age</span>
          <input
            type="number"
            min="0"
            max="120"
            value={filterRiskMin || ''}
            onChange={(e) => onFilterRiskChange(parseInt(e.target.value) || 0)}
            placeholder="Min"
            className="w-14 text-sm border border-gray-200 rounded-lg px-2 py-1.5 text-center focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          />
          <span className="text-xs text-gray-400">–</span>
          <input
            type="number"
            min="0"
            max="120"
            value={filterAgeMax || ''}
            onChange={(e) => onFilterAgeMaxChange(parseInt(e.target.value) || 0)}
            placeholder="Max"
            className="w-14 text-sm border border-gray-200 rounded-lg px-2 py-1.5 text-center focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          />
        </div>

        {/* Gender Filter */}
        <div className="flex items-center gap-1">
          {['All', 'Male', 'Female'].map(g => (
            <button
              key={g}
              onClick={() => onFilterGenderChange(g === 'All' ? '' : g)}
              className={`px-3 py-1.5 text-xs font-medium rounded-lg transition ${
                (g === 'All' && !filterGender) || filterGender === g
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {g}
            </button>
          ))}
        </div>

        {/* Text Search */}
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            value={filterText}
            onChange={(e) => onFilterTextChange(e.target.value)}
            placeholder="Search by name or ID..."
            className="w-full pl-9 pr-4 py-1.5 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          />
        </div>

        {/* Count */}
        <div className="flex items-center gap-1.5 text-sm text-gray-500">
          <Users className="w-4 h-4" />
          <span>
            {filteredCount === totalCount
              ? `${totalCount} members`
              : `${filteredCount} of ${totalCount}`}
          </span>
        </div>
      </div>
    </div>
  );
}

/* ── DashboardPage ─────────────────────────────────────────────────── */

export default function DashboardPage() {
  const [members, setMembers] = useState([]);
  const [profiles, setProfiles] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [sortField, setSortField] = useState('riskScore');
  const [sortDirection, setSortDirection] = useState('desc');
  const [filterRiskMin, setFilterRiskMin] = useState(0);
  const [filterAgeMax, setFilterAgeMax] = useState(0);
  const [filterText, setFilterText] = useState('');
  const [filterGender, setFilterGender] = useState('');
  const [lastRefresh, setLastRefresh] = useState(null);
  const [refreshing, setRefreshing] = useState(false);
  const prevChatHandler = useRef(null);

  const loadData = useCallback(() => {
    fetchDashboardData(setMembers, setProfiles, setLoading, setError);
    setLastRefresh(new Date());
  }, []);

  // Initial load
  useEffect(() => {
    loadData();
  }, [loadData]);

  // Listen for chat 'done' messages — when an analysis completes, refresh that member's profile
  useEffect(() => {
    const handleChatMsg = (msg) => {
      if (msg.type === 'done' && msg.meta?.memberId) {
        // A member was just analyzed — refresh their profile on the dashboard
        api.memberProfile(msg.meta.memberId).then(profileData => {
          setProfiles(prev => ({ ...prev, [msg.meta.memberId]: profileData }));
          setLastRefresh(new Date());
        }).catch(() => {});
      }
    };

    // Store previous handler and set ours
    // Note: onChatMessage is also used by ChatPage, so we chain
    const ws = getWebSocket();
    if (ws) {
      const origHandler = ws.onmessage;
      const wrappedHandler = (event) => {
        // Call original handler first
        if (origHandler) origHandler(event);
        // Then check for done messages
        try {
          const msg = JSON.parse(event.data);
          if (msg.type === 'done' && msg.meta?.memberId) {
            api.memberProfile(msg.meta.memberId).then(profileData => {
              setProfiles(prev => ({ ...prev, [msg.meta.memberId]: profileData }));
              setLastRefresh(new Date());
            }).catch(() => {});
          }
        } catch (e) {}
      };
      // Don't override — the api.js onmessage handler is already set
    }

    // Auto-refresh every 10 seconds to pick up pipeline updates
    const interval = setInterval(() => {
      const ws = getWebSocket();
      if (ws && ws.readyState === WebSocket.OPEN) {
        setRefreshing(true);
        fetchDashboardData(setMembers, setProfiles, () => {}, () => {}).then(() => {
          setLastRefresh(new Date());
          setRefreshing(false);
        });
      }
    }, 10000);

    return () => clearInterval(interval);
  }, []);

  const handleManualRefresh = useCallback(() => {
    setRefreshing(true);
    fetchDashboardData(setMembers, setProfiles, () => {}, setError).then(() => {
      setLastRefresh(new Date());
      setRefreshing(false);
    });
  }, []);

  const handleRetryProfile = useCallback(async (memberId) => {
    try {
      const profileData = await api.memberProfile(memberId);
      setProfiles(prev => ({ ...prev, [memberId]: profileData }));
    } catch (err) {
      setProfiles(prev => ({
        ...prev,
        [memberId]: { error: true, errorMsg: err.message || 'Failed to load' }
      }));
    }
  }, []);

  const displayMembers = useMemo(() =>
    applySortAndFilter(members, profiles, { sortField, sortDirection, filterRiskMin, filterAgeMax, filterText, filterGender }),
    [members, profiles, sortField, sortDirection, filterRiskMin, filterAgeMax, filterText, filterGender]
  );

  // Connection error state
  if (error) {
    return (
      <div className="p-8 max-w-7xl mx-auto">
        <div className="flex items-center gap-3 mb-6">
          <LayoutDashboard className="w-7 h-7 text-blue-600" />
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Member Dashboard</h1>
            <p className="text-gray-500 text-sm">Overview of all members and their analysis status</p>
          </div>
        </div>
        <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-center">
          <AlertTriangle className="w-10 h-10 text-red-400 mx-auto mb-3" />
          <p className="text-red-700 font-medium mb-2">{error}</p>
          <button
            onClick={loadData}
            className="inline-flex items-center gap-2 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-medium transition"
          >
            <RefreshCw className="w-4 h-4" /> Retry
          </button>
        </div>
      </div>
    );
  }

  // Loading state
  if (loading && members.length === 0) {
    return (
      <div className="p-8 max-w-7xl mx-auto">
        <div className="flex items-center gap-3 mb-6">
          <LayoutDashboard className="w-7 h-7 text-blue-600" />
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Member Dashboard</h1>
            <p className="text-gray-500 text-sm">Overview of all members and their analysis status</p>
          </div>
        </div>
        <div className="flex items-center justify-center h-64">
          <div className="text-center">
            <Loader2 className="w-8 h-8 animate-spin text-blue-500 mx-auto mb-3" />
            <p className="text-gray-500">Loading members...</p>
          </div>
        </div>
      </div>
    );
  }

  // Empty state
  if (!loading && members.length === 0) {
    return (
      <div className="p-8 max-w-7xl mx-auto">
        <div className="flex items-center gap-3 mb-6">
          <LayoutDashboard className="w-7 h-7 text-blue-600" />
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Member Dashboard</h1>
            <p className="text-gray-500 text-sm">Overview of all members and their analysis status</p>
          </div>
        </div>
        <div className="bg-white border border-gray-200 rounded-xl p-16 text-center">
          <Users className="w-12 h-12 text-gray-300 mx-auto mb-4" />
          <p className="text-lg font-medium text-gray-500">No members found</p>
          <p className="text-sm text-gray-400 mt-1">Members will appear here once they are added to the system.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-8 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <LayoutDashboard className="w-7 h-7 text-blue-600" />
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Member Dashboard</h1>
            <p className="text-gray-500 text-sm">Overview of all members and their analysis status</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          {lastRefresh && (
            <div className="flex items-center gap-1.5 text-xs text-gray-400">
              <Wifi className="w-3 h-3 text-green-500" />
              <span>Updated {lastRefresh.toLocaleTimeString()}</span>
            </div>
          )}
          <button
            onClick={handleManualRefresh}
            disabled={refreshing}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-lg transition disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${refreshing ? 'animate-spin' : ''}`} />
            {refreshing ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>
      </div>

      {/* Filter Bar */}
      <FilterBar
        sortField={sortField}
        sortDirection={sortDirection}
        onSortChange={(field, dir) => { setSortField(field); setSortDirection(dir); }}
        filterRiskMin={filterRiskMin}
        onFilterRiskChange={setFilterRiskMin}
        filterAgeMax={filterAgeMax}
        onFilterAgeMaxChange={setFilterAgeMax}
        filterText={filterText}
        onFilterTextChange={setFilterText}
        filterGender={filterGender}
        onFilterGenderChange={setFilterGender}
        totalCount={members.length}
        filteredCount={displayMembers.length}
      />

      {/* Member Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-6">
        {displayMembers.map(m => (
          <MemberSummaryCard
            key={m.memberId}
            member={m}
            profile={profiles[m.memberId]}
            profileLoading={!profiles[m.memberId]}
            onRetry={handleRetryProfile}
          />
        ))}
      </div>

      {/* No results after filtering */}
      {displayMembers.length === 0 && members.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-xl p-12 text-center mt-6">
          <Search className="w-10 h-10 text-gray-300 mx-auto mb-3" />
          <p className="text-gray-500 font-medium">No members match your filters</p>
          <p className="text-sm text-gray-400 mt-1">Try adjusting your search or filter criteria.</p>
        </div>
      )}
    </div>
  );
}
