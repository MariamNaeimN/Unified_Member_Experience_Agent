import { useState } from 'react';
import { Search, User, ChevronRight, ChevronDown, ChevronUp, Heart, AlertTriangle, Pill, Activity, Loader2, MessageSquare } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api';

function MemberCard({ member }) {
  const [expanded, setExpanded] = useState(false);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  async function handleExpand() {
    if (expanded) { setExpanded(false); return; }
    setExpanded(true);
    if (!profile) {
      setLoading(true);
      try {
        const data = await api.memberProfile(member.memberId);
        setProfile(data);
      } catch (e) {
        console.error('Profile fetch error:', e);
        setProfile({ error: true, errorMsg: e.message });
      }
      setLoading(false);
    }
  }

  const riskScore = profile?.patient?.riskScore ? parseInt(profile.patient.riskScore) : null;
  const riskColor = riskScore >= 80 ? 'text-red-600 bg-red-50' : riskScore >= 50 ? 'text-yellow-600 bg-yellow-50' : riskScore !== null ? 'text-green-600 bg-green-50' : 'text-gray-400 bg-gray-50';

  return (
    <div className="bg-white border border-gray-200 rounded-xl overflow-hidden hover:shadow-md transition-shadow">
      {/* Summary row */}
      <div className="flex items-center gap-4 p-4 cursor-pointer" onClick={handleExpand}>
        <div className="w-12 h-12 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-lg shrink-0">
          {member.firstName?.[0]}{member.lastName?.[0]}
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-gray-900">{member.firstName} {member.lastName}</p>
          <p className="text-sm text-gray-500">{member.memberId} · {member.planName} · {member.coverageStatus}</p>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {loading ? <Loader2 className="w-5 h-5 text-blue-500 animate-spin" /> :
            expanded ? <ChevronUp className="w-5 h-5 text-gray-400" /> : <ChevronDown className="w-5 h-5 text-gray-400" />
          }
        </div>
      </div>

      {/* Expanded detail */}
      {expanded && loading && (
        <div className="border-t border-gray-100 p-6 flex items-center justify-center">
          <Loader2 className="w-5 h-5 animate-spin text-blue-500 mr-2" />
          <span className="text-gray-500 text-sm">Loading profile...</span>
        </div>
      )}

      {expanded && !loading && profile?.error && (
        <div className="border-t border-gray-100 p-6 text-center text-red-500 text-sm">
          {profile.errorMsg || 'Failed to load profile'}
        </div>
      )}

      {expanded && !loading && profile && !profile.error && (
        <div className="border-t border-gray-100 px-4 pb-4">
          {/* Quick stats */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 py-4">
            <div className={`rounded-xl p-3 text-center ${riskColor}`}>
              <p className="text-2xl font-bold">{riskScore ?? '—'}</p>
              <p className="text-xs opacity-70">Risk Score</p>
            </div>
            <div className="rounded-xl p-3 text-center bg-orange-50 text-orange-700">
              <p className="text-2xl font-bold">{profile.conditions?.length || 0}</p>
              <p className="text-xs opacity-70">Conditions</p>
            </div>
            <div className="rounded-xl p-3 text-center bg-purple-50 text-purple-700">
              <p className="text-2xl font-bold">{profile.pharmacy?.length || 0}</p>
              <p className="text-xs opacity-70">Medications</p>
            </div>
            <div className="rounded-xl p-3 text-center bg-blue-50 text-blue-700">
              <p className="text-2xl font-bold">{profile.claims?.length || 0}</p>
              <p className="text-xs opacity-70">Claims</p>
            </div>
          </div>

          {/* Patient info */}
          <div className="grid grid-cols-2 md:grid-cols-3 gap-2 text-sm mb-4">
            {profile.member?.dob && <div className="bg-gray-50 rounded-lg px-3 py-2"><span className="text-gray-400 text-xs">DOB</span><p className="font-medium text-gray-700">{profile.member.dob}</p></div>}
            {profile.member?.gender && <div className="bg-gray-50 rounded-lg px-3 py-2"><span className="text-gray-400 text-xs">Gender</span><p className="font-medium text-gray-700">{profile.member.gender}</p></div>}
            {profile.patient?.livingSituation && <div className="bg-gray-50 rounded-lg px-3 py-2"><span className="text-gray-400 text-xs">Living</span><p className="font-medium text-gray-700">{profile.patient.livingSituation}</p></div>}
            {profile.patient?.bmi && <div className="bg-gray-50 rounded-lg px-3 py-2"><span className="text-gray-400 text-xs">BMI</span><p className="font-medium text-gray-700">{profile.patient.bmi}</p></div>}
            {profile.patient?.smokingStatus && <div className="bg-gray-50 rounded-lg px-3 py-2"><span className="text-gray-400 text-xs">Smoking</span><p className="font-medium text-gray-700">{profile.patient.smokingStatus}</p></div>}
            {profile.patient?.allergies?.length > 0 && <div className="bg-gray-50 rounded-lg px-3 py-2"><span className="text-gray-400 text-xs">Allergies</span><p className="font-medium text-gray-700">{profile.patient.allergies.join(', ')}</p></div>}
          </div>

          {/* Conditions */}
          {profile.conditions?.length > 0 && (
            <div className="mb-4">
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 flex items-center gap-1"><AlertTriangle className="w-3 h-3" /> Conditions</p>
              <div className="flex flex-wrap gap-2">
                {profile.conditions.map(c => (
                  <span key={c.conditionId} className={`text-xs px-2.5 py-1 rounded-full font-medium border ${
                    c.severity === 'Uncontrolled' || c.severity === 'Severe' ? 'bg-red-50 text-red-700 border-red-200' :
                    c.severity === 'Managed' || c.severity === 'Controlled' ? 'bg-green-50 text-green-700 border-green-200' :
                    'bg-yellow-50 text-yellow-700 border-yellow-200'
                  }`}>
                    {c.diagnosis} ({c.severity})
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Medications at risk */}
          {profile.pharmacy?.length > 0 && (
            <div className="mb-4">
              <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 flex items-center gap-1"><Pill className="w-3 h-3" /> Medications</p>
              <div className="space-y-1.5">
                {profile.pharmacy.map(rx => {
                  const adherence = parseInt(rx.adherencePercent || 0);
                  const isRisk = rx.status === 'Overdue' || adherence < 80;
                  return (
                    <div key={rx.rxId} className="flex items-center justify-between text-sm bg-gray-50 rounded-lg px-3 py-2">
                      <span className="text-gray-700">{rx.medication} {rx.dosage}</span>
                      <div className="flex items-center gap-2">
                        <span className={`text-xs font-medium ${adherence < 80 ? 'text-red-600' : 'text-green-600'}`}>{rx.adherencePercent}%</span>
                        <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${
                          rx.status === 'Overdue' ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'
                        }`}>{rx.status}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Action buttons */}
          <div className="flex gap-3 pt-2">
            <button onClick={() => navigate(`/members/${member.memberId}`)}
              className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-xl text-sm font-medium transition">
              <Heart className="w-4 h-4" /> Full Profile
            </button>
            <button onClick={() => navigate(`/chat?memberId=${member.memberId}&name=${member.firstName}`)}
              className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-sm font-medium transition">
              <MessageSquare className="w-4 h-4" /> Chat About {member.firstName}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export default function MembersPage() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [searched, setSearched] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSearch(e) {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    try {
      const data = await api.searchMembers(query);
      setResults(data.members || []);
      setSearched(true);
    } catch (err) { console.error(err); }
    finally { setLoading(false); }
  }

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-1">Members</h1>
      <p className="text-gray-500 mb-6">Search by name or member ID, click to expand details</p>

      <form onSubmit={handleSearch} className="flex gap-3 mb-8">
        <div className="relative flex-1">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
          <input value={query} onChange={e => setQuery(e.target.value)}
            placeholder="John Smith or M-10042"
            className="w-full pl-12 pr-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none" />
        </div>
        <button type="submit" disabled={loading}
          className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-xl transition disabled:opacity-50 flex items-center gap-2">
          {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Search className="w-4 h-4" />}
          Search
        </button>
      </form>

      {searched && results.length === 0 && (
        <div className="text-center py-16">
          <User className="w-12 h-12 text-gray-200 mx-auto mb-3" />
          <p className="text-gray-400">No members found for "{query}"</p>
        </div>
      )}

      <div className="space-y-3">
        {results.map(m => <MemberCard key={m.memberId} member={m} />)}
      </div>
    </div>
  );
}
