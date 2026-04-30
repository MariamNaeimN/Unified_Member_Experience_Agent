import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  ArrowLeft, Heart, AlertTriangle, Pill, Stethoscope, FileText, Activity,
  Brain, Target, Zap, MessageSquare, TrendingUp, ChevronDown, ChevronUp,
  Loader2, Database, Cpu
} from 'lucide-react';
import { api } from '../api';

/* ── Shared UI ─────────────────────────────────────────────────────── */

function Badge({ color, children }) {
  const colors = {
    red: 'bg-red-100 text-red-700', yellow: 'bg-yellow-100 text-yellow-700',
    green: 'bg-green-100 text-green-700', blue: 'bg-blue-100 text-blue-700',
    purple: 'bg-purple-100 text-purple-700', orange: 'bg-orange-100 text-orange-700',
    gray: 'bg-gray-100 text-gray-600',
  };
  return <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${colors[color] || colors.gray}`}>{children}</span>;
}

function Card({ title, icon: Icon, count, children, defaultOpen = true }) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
      <button onClick={() => setOpen(!open)}
        className="w-full px-5 py-3 border-b border-gray-100 flex items-center gap-2 hover:bg-gray-50 transition-colors">
        {Icon && <Icon className="w-4 h-4 text-blue-600" />}
        <h3 className="font-semibold text-gray-900 text-sm flex-1 text-left">{title}</h3>
        {count !== undefined && (
          <span className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">{count}</span>
        )}
        {open ? <ChevronUp className="w-4 h-4 text-gray-400" /> : <ChevronDown className="w-4 h-4 text-gray-400" />}
      </button>
      {open && <div className="p-5">{children}</div>}
    </div>
  );
}

function TabButton({ active, icon: Icon, label, onClick }) {
  return (
    <button onClick={onClick}
      className={`flex items-center gap-2 px-5 py-3 text-sm font-medium border-b-2 transition-colors ${
        active
          ? 'border-blue-600 text-blue-600'
          : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
      }`}>
      <Icon className="w-4 h-4" />
      {label}
    </button>
  );
}

function EmptyState({ message }) {
  return <p className="text-gray-400 text-sm py-2">{message}</p>;
}

/* ── Source Data Tab ───────────────────────────────────────────────── */

function SourceDataTab({ profile }) {
  const { member, patient, conditions = [], claims = [], pharmacy = [], careEvents = [] } = profile;

  return (
    <div className="space-y-4">
      {/* Source badge */}
      <div className="flex items-center gap-2 px-1">
        <Database className="w-4 h-4 text-emerald-600" />
        <span className="text-xs font-medium text-emerald-700 bg-emerald-50 px-2.5 py-1 rounded-full">
          Source: Member Data Table
        </span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Patient Info */}
        <Card title="Patient Info" icon={Heart}>
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div><span className="text-gray-400">Living:</span> {patient?.livingSituation || 'N/A'}</div>
            <div><span className="text-gray-400">BMI:</span> {patient?.bmi || 'N/A'}</div>
            <div><span className="text-gray-400">Blood:</span> {patient?.bloodType || 'N/A'}</div>
            <div><span className="text-gray-400">Smoking:</span> {patient?.smokingStatus || 'N/A'}</div>
            <div className="col-span-2">
              <span className="text-gray-400">Allergies:</span>{' '}
              {patient?.allergies?.length ? patient.allergies.join(', ') : 'None'}
            </div>
          </div>
        </Card>

        {/* Conditions */}
        <Card title="Conditions" icon={AlertTriangle} count={conditions.length}>
          {conditions.length === 0 ? <EmptyState message="No conditions on file" /> : (
            <div className="space-y-2">
              {conditions.map(c => (
                <div key={c.conditionId || c.recordType} className="flex items-center justify-between">
                  <span className="text-sm">{c.diagnosis}</span>
                  <Badge color={c.severity === 'Uncontrolled' ? 'red' : c.severity === 'Managed' ? 'green' : 'yellow'}>
                    {c.severity}
                  </Badge>
                </div>
              ))}
            </div>
          )}
        </Card>

        {/* Medications */}
        <Card title="Medications" icon={Pill} count={pharmacy.length}>
          {pharmacy.length === 0 ? <EmptyState message="No medications on file" /> : (
            <div className="space-y-3">
              {pharmacy.map(rx => (
                <div key={rx.rxId || rx.recordType} className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium">{rx.medication} {rx.dosage}</p>
                    <p className="text-xs text-gray-400">Adherence: {rx.adherencePercent}%</p>
                  </div>
                  <Badge color={rx.status === 'Overdue' ? 'red' : 'green'}>{rx.status}</Badge>
                </div>
              ))}
            </div>
          )}
        </Card>

        {/* Claims */}
        <Card title="Claims" icon={FileText} count={claims.length}>
          {claims.length === 0 ? <EmptyState message="No claims on file" /> : (
            <div className="space-y-2">
              {claims.slice(0, 8).map(cl => (
                <div key={cl.claimId || cl.recordType} className="flex items-center justify-between text-sm">
                  <div>
                    <p>{cl.diagnosisDesc}</p>
                    <p className="text-xs text-gray-400">{cl.serviceDate} · {cl.claimType}</p>
                  </div>
                  <span className="font-medium">${cl.paidAmount}</span>
                </div>
              ))}
              {claims.length > 8 && (
                <p className="text-xs text-gray-400 pt-1">+ {claims.length - 8} more claims</p>
              )}
            </div>
          )}
        </Card>
      </div>

      {/* Care Events — full width */}
      <Card title="Care Events" icon={Activity} count={careEvents.length}>
        {careEvents.length === 0 ? <EmptyState message="No care events on file" /> : (
          <div className="space-y-3">
            {careEvents.sort((a, b) => (b.date || '').localeCompare(a.date || '')).slice(0, 10).map(ev => (
              <div key={ev.eventId || ev.recordType} className="flex items-start gap-3">
                <Badge color={ev.eventType === 'ER_Visit' ? 'red' : ev.eventType === 'Missed_Appointment' ? 'yellow' : 'blue'}>
                  {ev.eventType?.replace(/_/g, ' ')}
                </Badge>
                <div className="flex-1 text-sm">
                  <p>{ev.facilityName} — {ev.date}</p>
                  {ev.notes && <p className="text-xs text-gray-400 mt-0.5 line-clamp-2">{ev.notes}</p>}
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}

/* ── Agent Analysis Tab ───────────────────────────────────────────── */

function AgentAnalysisTab({ profile }) {
  // Deduplicate: keep only the latest AI decision (by updatedAt)
  const allDecisions = profile.aiDecisions || [];
  const latestDecision = allDecisions.length > 0
    ? [allDecisions.sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''))[0]]
    : [];
  
  // Deduplicate care gaps and interventions — keep only those matching the latest decisionId
  const latestDecisionId = latestDecision[0]?.decisionId || '';
  const allCareGaps = profile.careGaps || [];
  const careGaps = latestDecisionId
    ? allCareGaps.filter(g => g.decisionId === latestDecisionId || !g.decisionId)
    : allCareGaps;
  const allInterventions = profile.interventions || [];
  const interventions = latestDecisionId
    ? allInterventions.filter(inv => inv.decisionId === latestDecisionId || !inv.decisionId)
    : allInterventions;
  const summaries = profile.summaries || [];
  
  const aiDecisions = latestDecision;
  const hasData = aiDecisions.length || careGaps.length || interventions.length || summaries.length;

  if (!hasData) {
    return (
      <div className="text-center py-16">
        <div className="w-16 h-16 bg-purple-50 rounded-full flex items-center justify-center mx-auto mb-4">
          <Brain className="w-8 h-8 text-purple-300" />
        </div>
        <p className="text-lg font-medium text-gray-500">No agent analysis yet</p>
        <p className="text-sm text-gray-400 mt-1">Chat with the AI agent to generate insights for this member</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Source badge */}
      <div className="flex items-center gap-2 px-1">
        <Cpu className="w-4 h-4 text-purple-600" />
        <span className="text-xs font-medium text-purple-700 bg-purple-50 px-2.5 py-1 rounded-full">
          Source: Agent Output Table
        </span>
      </div>

      {/* AI Decisions */}
      {aiDecisions.length > 0 && (
        <Card title="AI Decisions" icon={Brain} count={aiDecisions.length}>
          <div className="space-y-4">
            {aiDecisions.map((d, i) => (
              <div key={d.decisionId || i} className="border border-gray-100 rounded-lg p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-mono text-gray-400">{d.decisionId}</span>
                  {d.confidence && (
                    <Badge color={parseFloat(d.confidence) >= 0.8 ? 'green' : parseFloat(d.confidence) >= 0.5 ? 'yellow' : 'red'}>
                      Confidence: {Math.round(parseFloat(d.confidence) * 100)}%
                    </Badge>
                  )}
                </div>
                {d.analysis && (
                  <div className="mb-2">
                    <p className="text-xs text-gray-400 mb-1">Analysis</p>
                    <p className="text-sm text-gray-700 whitespace-pre-wrap">{d.analysis}</p>
                  </div>
                )}
                {d.riskAssessment && (
                  <div className="mb-2">
                    <p className="text-xs text-gray-400 mb-1">Risk Assessment</p>
                    <p className="text-sm text-gray-700">{d.riskAssessment}</p>
                  </div>
                )}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-2 mt-3">
                  {d.claimsInsight && (
                    <div className="bg-blue-50 rounded-lg p-2">
                      <p className="text-xs text-blue-500 mb-0.5">Claims Insight</p>
                      <p className="text-xs text-blue-800">{d.claimsInsight}</p>
                    </div>
                  )}
                  {d.careHistoryInsight && (
                    <div className="bg-green-50 rounded-lg p-2">
                      <p className="text-xs text-green-500 mb-0.5">Care History</p>
                      <p className="text-xs text-green-800">{d.careHistoryInsight}</p>
                    </div>
                  )}
                  {d.medicationInsight && (
                    <div className="bg-orange-50 rounded-lg p-2">
                      <p className="text-xs text-orange-500 mb-0.5">Medication</p>
                      <p className="text-xs text-orange-800">{d.medicationInsight}</p>
                    </div>
                  )}
                </div>
                {d.updatedAt && (
                  <p className="text-xs text-gray-400 mt-2">Generated: {new Date(d.updatedAt).toLocaleString()}</p>
                )}
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Care Gaps */}
      {careGaps.length > 0 && (
        <Card title="Care Gaps" icon={Target} count={careGaps.length}>
          <div className="space-y-3">
            {careGaps.map((g, i) => (
              <div key={g.gapId || i} className="border border-gray-100 rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <p className="text-sm font-medium text-gray-900">{g.type || g.gapType || 'Gap'}</p>
                  <div className="flex items-center gap-2">
                    <Badge color={
                      g.priority === 'CRITICAL' ? 'red' :
                      g.priority === 'HIGH' ? 'orange' :
                      g.priority === 'MEDIUM' ? 'yellow' : 'green'
                    }>{g.priority}</Badge>
                    <Badge color={g.status === 'Open' ? 'blue' : 'gray'}>{g.status}</Badge>
                  </div>
                </div>
                <div className="flex gap-4 text-xs text-gray-400 mb-2">
                  {g.protocol && <span>Protocol: {g.protocol}</span>}
                  {g.dueWithin && <span>Due: {g.dueWithin}</span>}
                </div>
                {g.details && (
                  <p className="text-sm text-gray-600 bg-gray-50 rounded-lg p-2 mb-2">{g.details}</p>
                )}
                {g.actionItems && g.actionItems.length > 0 && (
                  <div className="mt-2">
                    <p className="text-xs text-gray-400 mb-1">Action Items:</p>
                    <ul className="space-y-1">
                      {g.actionItems.map((item, j) => (
                        <li key={j} className="text-xs text-gray-700 flex items-start gap-2">
                          <span className="text-blue-500 mt-0.5">•</span>
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Interventions */}
      {interventions.length > 0 && (
        <Card title="Interventions" icon={Zap} count={interventions.length}>
          <div className="space-y-2">
            {interventions.map((inv, i) => (
              <div key={inv.interventionId || i} className="border border-gray-100 rounded-lg p-3">
                <div className="flex items-center justify-between mb-1">
                  <Badge color={
                    inv.type === 'SMS' ? 'blue' :
                    inv.type === 'TASK' ? 'purple' :
                    inv.type === 'ALERT' ? 'red' :
                    inv.type === 'REFERRAL' ? 'green' : 'gray'
                  }>{inv.type}</Badge>
                  <Badge color={inv.status === 'Triggered' ? 'orange' : 'green'}>{inv.status}</Badge>
                </div>
                <p className="text-sm text-gray-700 mt-1">{inv.message}</p>
                {inv.target && <p className="text-xs text-gray-400 mt-1">Target: {inv.target}</p>}
                {inv.linkedGap && <p className="text-xs text-gray-400">Linked Gap: {inv.linkedGap}</p>}
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Summaries / Talking Points */}
      {summaries.length > 0 && (
        <Card title="Summaries" icon={MessageSquare} count={summaries.length}>
          <div className="space-y-3">
            {summaries.map((s, i) => (
              <div key={i} className="border border-gray-100 rounded-lg p-4">
                {s.talkingPoints && s.talkingPoints.length > 0 && (
                  <div>
                    <p className="text-xs text-gray-400 mb-2">Talking Points</p>
                    <ol className="list-decimal list-inside space-y-1">
                      {s.talkingPoints.map((pt, j) => (
                        <li key={j} className="text-sm text-gray-700">{pt}</li>
                      ))}
                    </ol>
                  </div>
                )}
                {s.updatedAt && (
                  <p className="text-xs text-gray-400 mt-2">Generated: {new Date(s.updatedAt).toLocaleString()}</p>
                )}
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}

/* ── Main Profile Page ────────────────────────────────────────────── */

export default function ProfilePage() {
  const { memberId } = useParams();
  const navigate = useNavigate();
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('source');

  useEffect(() => {
    setLoading(true);
    api.memberProfile(memberId)
      .then(data => { setProfile(data); setLoading(false); })
      .catch(() => setLoading(false));
  }, [memberId]);

  if (loading) return (
    <div className="flex items-center justify-center h-96">
      <div className="text-center">
        <Loader2 className="w-8 h-8 animate-spin text-blue-500 mx-auto mb-3" />
        <p className="text-gray-500">Loading profile...</p>
      </div>
    </div>
  );

  if (!profile?.member) return (
    <div className="p-8 text-center">
      <p className="text-red-500 text-lg">Member not found</p>
      <button onClick={() => navigate('/dashboard')} className="mt-4 text-blue-600 hover:underline text-sm">
        Back to Dashboard
      </button>
    </div>
  );

  const { member, patient } = profile;
  const riskScore = parseInt(patient?.riskScore || 0);
  const riskColor = riskScore >= 80 ? 'text-red-600' : riskScore >= 50 ? 'text-yellow-600' : 'text-green-600';

  const agentDataCount = Math.min(profile.aiDecisions?.length || 0, 1) + (profile.careGaps?.length || 0)
    + (profile.interventions?.length || 0) + (profile.summaries?.length || 0);

  return (
    <div className="p-8 max-w-6xl mx-auto">
      {/* Back button */}
      <button onClick={() => navigate('/dashboard')}
        className="flex items-center gap-1 text-sm text-gray-500 hover:text-blue-600 mb-4">
        <ArrowLeft className="w-4 h-4" /> Back to Dashboard
      </button>

      {/* Header card */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-6 flex items-center gap-6">
        <div className="w-16 h-16 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center text-xl font-bold">
          {member.firstName?.[0]}{member.lastName?.[0]}
        </div>
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-gray-900">{member.firstName} {member.lastName}</h1>
          <p className="text-gray-500">{memberId} · {member.planName} · {member.gender} · DOB: {member.dob}</p>
        </div>
        <div className="text-center">
          <div className={`text-3xl font-bold ${riskColor}`}>{riskScore}</div>
          <p className="text-xs text-gray-400">Risk Score</p>
        </div>
      </div>

      {/* Tab bar */}
      <div className="bg-white rounded-xl border border-gray-200 mb-6">
        <div className="flex border-b border-gray-200">
          <TabButton
            active={activeTab === 'source'}
            icon={Database}
            label="Member Data"
            onClick={() => setActiveTab('source')}
          />
          <TabButton
            active={activeTab === 'agent'}
            icon={Brain}
            label={`Agent Analysis${agentDataCount > 0 ? ` (${agentDataCount})` : ''}`}
            onClick={() => setActiveTab('agent')}
          />
        </div>

        <div className="p-6">
          {activeTab === 'source' && <SourceDataTab profile={profile} />}
          {activeTab === 'agent' && <AgentAnalysisTab profile={profile} />}
        </div>
      </div>
    </div>
  );
}
