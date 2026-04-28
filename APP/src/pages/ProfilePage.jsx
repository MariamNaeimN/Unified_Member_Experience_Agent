import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Heart, AlertTriangle, Pill, Stethoscope, FileText, Activity, Users } from 'lucide-react';
import { api } from '../api';

function Badge({ color, children }) {
  const colors = {
    red: 'bg-red-100 text-red-700', yellow: 'bg-yellow-100 text-yellow-700',
    green: 'bg-green-100 text-green-700', blue: 'bg-blue-100 text-blue-700',
    gray: 'bg-gray-100 text-gray-600',
  };
  return <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${colors[color] || colors.gray}`}>{children}</span>;
}

function Card({ title, icon: Icon, children }) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
      <div className="px-5 py-3 border-b border-gray-100 flex items-center gap-2">
        {Icon && <Icon className="w-4 h-4 text-blue-600" />}
        <h3 className="font-semibold text-gray-900 text-sm">{title}</h3>
      </div>
      <div className="p-5">{children}</div>
    </div>
  );
}

export default function ProfilePage() {
  const { memberId } = useParams();
  const navigate = useNavigate();
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.memberProfile(memberId).then(data => { setProfile(data); setLoading(false); });
  }, [memberId]);

  if (loading) return <div className="p-8 text-gray-400">Loading profile...</div>;
  if (!profile?.member) return <div className="p-8 text-red-500">Member not found</div>;

  const { member, patient, conditions = [], claims = [], pharmacy = [], careEvents = [] } = profile;
  const riskScore = parseInt(patient?.riskScore || 0);
  const riskColor = riskScore >= 80 ? 'red' : riskScore >= 50 ? 'yellow' : 'green';

  return (
    <div className="p-8 max-w-6xl mx-auto">
      <button onClick={() => navigate('/members')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-blue-600 mb-4">
        <ArrowLeft className="w-4 h-4" /> Back to Members
      </button>

      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-6 flex items-center gap-6">
        <div className="w-16 h-16 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center text-xl font-bold">
          {member.firstName?.[0]}{member.lastName?.[0]}
        </div>
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-gray-900">{member.firstName} {member.lastName}</h1>
          <p className="text-gray-500">{memberId} · {member.planName} · {member.gender} · DOB: {member.dob}</p>
        </div>
        <div className="text-center">
          <div className={`text-3xl font-bold ${riskColor === 'red' ? 'text-red-600' : riskColor === 'yellow' ? 'text-yellow-600' : 'text-green-600'}`}>
            {riskScore}
          </div>
          <p className="text-xs text-gray-400">Risk Score</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
        <Card title="Patient Info" icon={Heart}>
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div><span className="text-gray-400">Living:</span> {patient?.livingSituation}</div>
            <div><span className="text-gray-400">BMI:</span> {patient?.bmi}</div>
            <div><span className="text-gray-400">Blood:</span> {patient?.bloodType}</div>
            <div><span className="text-gray-400">Smoking:</span> {patient?.smokingStatus}</div>
            <div className="col-span-2"><span className="text-gray-400">Allergies:</span> {patient?.allergies?.length ? patient.allergies.join(', ') : 'None'}</div>
          </div>
        </Card>

        <Card title={`Conditions (${conditions.length})`} icon={AlertTriangle}>
          {conditions.length === 0 ? <p className="text-gray-400 text-sm">No conditions</p> :
            <div className="space-y-2">
              {conditions.map(c => (
                <div key={c.conditionId} className="flex items-center justify-between">
                  <span className="text-sm">{c.diagnosis}</span>
                  <Badge color={c.severity === 'Uncontrolled' ? 'red' : c.severity === 'Managed' ? 'green' : 'yellow'}>{c.severity}</Badge>
                </div>
              ))}
            </div>
          }
        </Card>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
        <Card title={`Medications (${pharmacy.length})`} icon={Pill}>
          {pharmacy.length === 0 ? <p className="text-gray-400 text-sm">No medications</p> :
            <div className="space-y-3">
              {pharmacy.map(rx => (
                <div key={rx.rxId} className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium">{rx.medication} {rx.dosage}</p>
                    <p className="text-xs text-gray-400">Adherence: {rx.adherencePercent}%</p>
                  </div>
                  <Badge color={rx.status === 'Overdue' ? 'red' : 'green'}>{rx.status}</Badge>
                </div>
              ))}
            </div>
          }
        </Card>

        <Card title={`Claims (${claims.length})`} icon={FileText}>
          {claims.length === 0 ? <p className="text-gray-400 text-sm">No claims</p> :
            <div className="space-y-2">
              {claims.slice(0, 5).map(cl => (
                <div key={cl.claimId} className="flex items-center justify-between text-sm">
                  <div>
                    <p>{cl.diagnosisDesc}</p>
                    <p className="text-xs text-gray-400">{cl.serviceDate} · {cl.claimType}</p>
                  </div>
                  <span className="font-medium">${cl.paidAmount}</span>
                </div>
              ))}
            </div>
          }
        </Card>
      </div>

      <Card title={`Care Events (${careEvents.length})`} icon={Activity}>
        {careEvents.length === 0 ? <p className="text-gray-400 text-sm">No care events</p> :
          <div className="space-y-3">
            {careEvents.sort((a, b) => b.date?.localeCompare(a.date)).slice(0, 8).map(ev => (
              <div key={ev.eventId} className="flex items-start gap-3">
                <Badge color={ev.eventType === 'ER_Visit' ? 'red' : ev.eventType === 'Missed_Appointment' ? 'yellow' : 'blue'}>
                  {ev.eventType?.replace('_', ' ')}
                </Badge>
                <div className="flex-1 text-sm">
                  <p>{ev.facilityName} — {ev.date}</p>
                  {ev.notes && <p className="text-xs text-gray-400 mt-0.5 line-clamp-2">{ev.notes}</p>}
                </div>
              </div>
            ))}
          </div>
        }
      </Card>

      <div className="mt-6 text-center">
        <button onClick={() => navigate(`/chat?memberId=${memberId}`)}
          className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-xl transition font-medium">
          Chat with Agent about {member.firstName}
        </button>
      </div>
    </div>
  );
}
