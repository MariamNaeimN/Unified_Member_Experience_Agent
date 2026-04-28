import { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Loader2, AlertTriangle, CheckCircle, Shield, MessageSquare, Pill, Phone, ArrowUpRight, ClipboardList, AlertCircle } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { api } from '../api';

// Typing animation hook
function useStreamText(text, speed = 12) {
  const [displayed, setDisplayed] = useState('');
  const [done, setDone] = useState(false);
  useEffect(() => {
    if (!text) { setDisplayed(''); setDone(true); return; }
    setDisplayed('');
    setDone(false);
    let i = 0;
    const id = setInterval(() => {
      i += 1 + Math.floor(Math.random() * 2);
      if (i >= text.length) { setDisplayed(text); setDone(true); clearInterval(id); }
      else setDisplayed(text.slice(0, i));
    }, speed);
    return () => clearInterval(id);
  }, [text, speed]);
  return { displayed, done };
}

// Parse the agent response into structured sections
function parseResponse(text) {
  if (!text) return null;
  const sections = { analysis: '', risk: '', claims: '', care: '', medication: '', gaps: [], actions: [], talkingPoints: [] };

  const lines = text.split('\n');
  let current = 'analysis';

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (trimmed.startsWith('Risk Assessment:')) { sections.risk = trimmed.replace('Risk Assessment:', '').trim(); current = 'risk'; }
    else if (trimmed.startsWith('Claims Pattern:')) { sections.claims = trimmed.replace('Claims Pattern:', '').trim(); current = 'claims'; }
    else if (trimmed.startsWith('Care Engagement:')) { sections.care = trimmed.replace('Care Engagement:', '').trim(); current = 'care'; }
    else if (trimmed.startsWith('Medication Status:')) { sections.medication = trimmed.replace('Medication Status:', '').trim(); current = 'medication'; }
    else if (trimmed === 'Care Gaps Identified:') { current = 'gaps'; }
    else if (trimmed === 'Actions Triggered:') { current = 'actions'; }
    else if (trimmed === 'Talking Points for Your Call:') { current = 'talkingPoints'; }
    else if (current === 'gaps' && (trimmed.startsWith('!!') || trimmed.startsWith('-'))) {
      const match = trimmed.match(/^[!-]+\s*(.+?)\s*\(Priority:\s*(\w+),\s*Due:\s*(.+?)\)$/);
      if (match) sections.gaps.push({ type: match[1], priority: match[2], due: match[3] });
      else sections.gaps.push({ type: trimmed.replace(/^[!-]+\s*/, ''), priority: 'MEDIUM', due: '' });
    }
    else if (current === 'actions' && trimmed.startsWith('[')) {
      const match = trimmed.match(/^\[(\w+)\]\s*(.+)$/);
      if (match) sections.actions.push({ type: match[1], message: match[2] });
    }
    else if (current === 'talkingPoints' && /^\d+\./.test(trimmed)) {
      sections.talkingPoints.push(trimmed.replace(/^\d+\.\s*/, ''));
    }
    else if (current === 'analysis' && !sections.analysis) { sections.analysis = trimmed; }
    else if (current === 'analysis') { sections.analysis += ' ' + trimmed; }
  }
  return sections;
}

// Structured agent response component
function AgentResponse({ text, meta, isLatest }) {
  const { displayed, done } = useStreamText(isLatest ? text : null, 8);
  const content = isLatest && !done ? displayed : text;
  const sections = done || !isLatest ? parseResponse(text) : null;

  // While streaming, show raw text with cursor
  if (isLatest && !done) {
    return (
      <div className="text-sm leading-relaxed text-gray-700">
        {content}<span className="inline-block w-2 h-4 bg-blue-500 animate-pulse ml-0.5 align-middle rounded-sm" />
      </div>
    );
  }

  // Once done, show structured layout
  if (!sections || !sections.analysis) {
    return <p className="text-sm leading-relaxed text-gray-700 whitespace-pre-wrap">{text}</p>;
  }

  const priorityColors = { CRITICAL: 'border-red-500 bg-red-50', HIGH: 'border-orange-400 bg-orange-50', MEDIUM: 'border-yellow-400 bg-yellow-50', LOW: 'border-green-400 bg-green-50' };
  const actionIcons = { SMS: MessageSquare, TASK: ClipboardList, ALERT: AlertCircle, REFERRAL: ArrowUpRight };
  const actionColors = { SMS: 'text-blue-600 bg-blue-50', TASK: 'text-purple-600 bg-purple-50', ALERT: 'text-red-600 bg-red-50', REFERRAL: 'text-green-600 bg-green-50' };

  return (
    <div className="space-y-4">
      {/* Analysis */}
      <p className="text-sm leading-relaxed text-gray-700">{sections.analysis}</p>

      {/* Risk Badge */}
      {sections.risk && (
        <div className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium ${
          sections.risk.startsWith('HIGH') ? 'bg-red-50 text-red-700 border border-red-200' :
          sections.risk.startsWith('MEDIUM') ? 'bg-yellow-50 text-yellow-700 border border-yellow-200' :
          'bg-green-50 text-green-700 border border-green-200'
        }`}>
          <Shield className="w-4 h-4" />
          <span>Risk: {sections.risk}</span>
        </div>
      )}

      {/* Insights Grid */}
      {(sections.claims || sections.care || sections.medication) && (
        <div className="grid grid-cols-1 gap-2">
          {sections.claims && (
            <div className="flex items-start gap-2 bg-gray-50 rounded-lg px-3 py-2 text-xs text-gray-600">
              <span className="font-semibold text-gray-500 shrink-0">Claims:</span> {sections.claims}
            </div>
          )}
          {sections.care && (
            <div className="flex items-start gap-2 bg-gray-50 rounded-lg px-3 py-2 text-xs text-gray-600">
              <span className="font-semibold text-gray-500 shrink-0">Care:</span> {sections.care}
            </div>
          )}
          {sections.medication && (
            <div className="flex items-start gap-2 bg-gray-50 rounded-lg px-3 py-2 text-xs text-gray-600">
              <span className="font-semibold text-gray-500 shrink-0">Meds:</span> {sections.medication}
            </div>
          )}
        </div>
      )}

      {/* Care Gaps */}
      {sections.gaps.length > 0 && (
        <div>
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Care Gaps</p>
          <div className="space-y-1.5">
            {sections.gaps.map((g, i) => (
              <div key={i} className={`flex items-center justify-between border-l-3 pl-3 py-1.5 rounded-r-lg text-sm ${priorityColors[g.priority] || priorityColors.MEDIUM}`}>
                <span className="text-gray-700">{g.type}</span>
                <div className="flex items-center gap-2 text-xs">
                  {g.due && <span className="text-gray-400">Due: {g.due}</span>}
                  <span className={`px-2 py-0.5 rounded-full font-semibold text-xs ${
                    g.priority === 'CRITICAL' ? 'bg-red-200 text-red-800' :
                    g.priority === 'HIGH' ? 'bg-orange-200 text-orange-800' : 'bg-yellow-200 text-yellow-800'
                  }`}>{g.priority}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Actions Triggered */}
      {sections.actions.length > 0 && (
        <div>
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">Actions Triggered</p>
          <div className="space-y-2">
            {sections.actions.map((a, i) => {
              const Icon = actionIcons[a.type] || CheckCircle;
              const color = actionColors[a.type] || 'text-gray-600 bg-gray-50';
              return (
                <div key={i} className="flex items-start gap-3 text-sm">
                  <div className={`w-7 h-7 rounded-full flex items-center justify-center shrink-0 ${color}`}>
                    <Icon className="w-3.5 h-3.5" />
                  </div>
                  <div>
                    <span className="text-xs font-semibold text-gray-400">{a.type}</span>
                    <p className="text-gray-700">{a.message}</p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Talking Points */}
      {sections.talkingPoints.length > 0 && (
        <div className="bg-blue-50 border border-blue-100 rounded-lg p-3">
          <p className="text-xs font-semibold text-blue-600 uppercase tracking-wide mb-2 flex items-center gap-1">
            <Phone className="w-3 h-3" /> Talking Points
          </p>
          <ol className="space-y-1.5 text-sm text-blue-900">
            {sections.talkingPoints.map((p, i) => (
              <li key={i} className="flex gap-2">
                <span className="text-blue-400 font-semibold shrink-0">{i + 1}.</span>
                <span>{p}</span>
              </li>
            ))}
          </ol>
        </div>
      )}
    </div>
  );
}

export default function ChatPage() {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [activeMember, setActiveMember] = useState(null);
  const bottomRef = useRef(null);
  const sendingRef = useRef(false);
  const [searchParams, setSearchParams] = useSearchParams();

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages, loading]);

  // Auto-send when navigated from member profile
  useEffect(() => {
    const memberId = searchParams.get('memberId');
    if (memberId && !sendingRef.current) {
      sendingRef.current = true;
      setSearchParams({}, { replace: true });
      setActiveMember(memberId);
      const msg = `Tell me about ${memberId}`;
      setMessages(prev => [...prev, { role: 'user', text: msg }]);
      setLoading(true);
      api.chat(memberId, msg).then(data => {
        setMessages(prev => [...prev, {
          role: 'agent', text: data.agentResponse || 'No response',
          meta: { decisionId: data.decisionId, careGaps: data.careGaps, interventions: data.interventions, cached: data.cached, memberId }
        }]);
      }).catch(err => {
        setMessages(prev => [...prev, { role: 'system', text: 'Error: ' + err.message }]);
      }).finally(() => { setLoading(false); sendingRef.current = false; });
    }
  }, [searchParams]);

  async function handleSend(e) {
    e.preventDefault();
    if (!input.trim() || loading) return;
    const msg = input.trim();
    setInput('');

    const memberMatch = msg.match(/M-\d{5}/i);
    const memberId = memberMatch ? memberMatch[0].toUpperCase() : activeMember;
    if (!memberId) {
      setMessages(prev => [...prev, { role: 'system', text: 'Include a member ID in your message (e.g., M-10042)' }]);
      return;
    }
    if (memberMatch) setActiveMember(memberMatch[0].toUpperCase());

    setMessages(prev => [...prev, { role: 'user', text: msg }]);
    setLoading(true);

    try {
      const data = await api.chat(memberId, msg);
      setMessages(prev => [...prev, {
        role: 'agent', text: data.agentResponse || 'No response',
        meta: { decisionId: data.decisionId, careGaps: data.careGaps, interventions: data.interventions, cached: data.cached, memberId }
      }]);
    } catch (err) {
      setMessages(prev => [...prev, { role: 'system', text: 'Error: ' + err.message }]);
    } finally { setLoading(false); }
  }

  return (
    <div className="h-screen flex flex-col">
      {/* Header */}
      <div className="border-b border-gray-200 bg-white px-6 py-4 flex items-center justify-between shrink-0">
        <div>
          <h1 className="text-lg font-bold text-gray-900">AI Care Agent</h1>
          <p className="text-sm text-gray-500">
            {activeMember ? `Analyzing ${activeMember}` : 'Ask about any member by ID'}
          </p>
        </div>
        {activeMember && (
          <span className="px-3 py-1.5 bg-blue-100 text-blue-700 rounded-full text-sm font-semibold">{activeMember}</span>
        )}
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-6 space-y-5">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <div className="w-20 h-20 bg-blue-50 rounded-full flex items-center justify-center mb-4">
              <Bot className="w-10 h-10 text-blue-300" />
            </div>
            <p className="text-lg font-medium text-gray-500">How can I help you today?</p>
            <p className="text-sm mt-1">Try: "Tell me about M-10042"</p>
            <div className="flex gap-2 mt-4">
              {['M-10042', 'M-10052', 'M-10059'].map(id => (
                <button key={id} onClick={() => { setInput(`Tell me about ${id}`); }}
                  className="px-3 py-1.5 bg-white border border-gray-200 rounded-full text-sm text-gray-600 hover:border-blue-300 hover:text-blue-600 transition">
                  {id}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((msg, i) => (
          <div key={i} className={`flex gap-3 ${msg.role === 'user' ? 'justify-end' : ''}`}>
            {msg.role !== 'user' && (
              <div className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 mt-1 ${
                msg.role === 'agent' ? 'bg-blue-100 text-blue-600' : 'bg-yellow-100 text-yellow-600'
              }`}>
                {msg.role === 'agent' ? <Bot className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
              </div>
            )}
            <div className={`rounded-2xl px-5 py-4 ${
              msg.role === 'user' ? 'bg-blue-600 text-white max-w-lg' :
              msg.role === 'agent' ? 'bg-white border border-gray-200 shadow-sm max-w-3xl w-full' :
              'bg-yellow-50 border border-yellow-200 max-w-lg'
            }`}>
              {msg.role === 'agent' && msg.meta && (
                <div className="flex flex-wrap gap-2 mb-3 pb-3 border-b border-gray-100">
                  {msg.meta.memberId && (
                    <span className="text-xs bg-gray-100 text-gray-600 px-2 py-1 rounded-full font-medium">{msg.meta.memberId}</span>
                  )}
                  {msg.meta.careGaps > 0 && (
                    <span className="flex items-center gap-1 text-xs text-red-600 bg-red-50 px-2 py-1 rounded-full font-medium">
                      <AlertTriangle className="w-3 h-3" /> {msg.meta.careGaps} care gaps
                    </span>
                  )}
                  {msg.meta.interventions > 0 && (
                    <span className="flex items-center gap-1 text-xs text-green-600 bg-green-50 px-2 py-1 rounded-full font-medium">
                      <CheckCircle className="w-3 h-3" /> {msg.meta.interventions} actions
                    </span>
                  )}
                  {msg.meta.cached && (
                    <span className="text-xs text-gray-400 bg-gray-50 px-2 py-1 rounded-full">cached</span>
                  )}
                </div>
              )}
              {msg.role === 'agent' ? (
                <AgentResponse text={msg.text} meta={msg.meta} isLatest={i === messages.length - 1} />
              ) : (
                <p className="text-sm leading-relaxed">{msg.text}</p>
              )}
            </div>
            {msg.role === 'user' && (
              <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center shrink-0 mt-1">
                <User className="w-4 h-4 text-gray-600" />
              </div>
            )}
          </div>
        ))}

        {loading && (
          <div className="flex gap-3">
            <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center mt-1">
              <Loader2 className="w-4 h-4 text-blue-600 animate-spin" />
            </div>
            <div className="bg-white border border-gray-200 rounded-2xl px-5 py-4 shadow-sm max-w-md">
              <div className="flex items-center gap-3">
                <div className="flex gap-1">
                  <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
                  <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
                  <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
                </div>
                <p className="text-sm text-gray-500">Analyzing member profile with Bedrock AI...</p>
              </div>
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSend} className="border-t border-gray-200 bg-white p-4 shrink-0">
        <div className="flex gap-3 max-w-4xl mx-auto">
          <input value={input} onChange={e => setInput(e.target.value)}
            placeholder="Ask about a member... (e.g., Tell me about M-10042)"
            className="flex-1 px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm"
            disabled={loading} />
          <button type="submit" disabled={loading || !input.trim()}
            className="px-5 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-xl transition disabled:opacity-50 flex items-center gap-2 text-sm font-medium">
            <Send className="w-4 h-4" /> Send
          </button>
        </div>
      </form>
    </div>
  );
}
