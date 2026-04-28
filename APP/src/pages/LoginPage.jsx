import { useState } from 'react';
import { Heart, Shield, UserPlus, ArrowLeft, Mail, Sparkles } from 'lucide-react';
import { login, signUp, confirmSignUp } from '../auth';

export default function LoginPage({ onLogin }) {
  const [mode, setMode] = useState('login');
  const [name, setName] = useState('');
  const [email, setEmail] = useState('sarah@example.com');
  const [password, setPassword] = useState('TestPass123!');
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [pendingEmail, setPendingEmail] = useState('');

  async function handleLogin(e) {
    e.preventDefault(); setLoading(true); setError('');
    try { onLogin(await login(email, password)); }
    catch (err) { setError(err.message); }
    finally { setLoading(false); }
  }
  async function handleSignUp(e) {
    e.preventDefault();
    if (password.length < 8) { setError('Password must be at least 8 characters'); return; }
    setLoading(true); setError('');
    try { await signUp(name, email, password); setPendingEmail(email); setMode('confirm'); }
    catch (err) { setError(err.message); }
    finally { setLoading(false); }
  }
  async function handleConfirm(e) {
    e.preventDefault(); setLoading(true); setError('');
    try { await confirmSignUp(pendingEmail, code); onLogin(await login(pendingEmail, password)); }
    catch (err) { setError(err.message); }
    finally { setLoading(false); }
  }

  const inputCls = "w-full px-4 py-3 rounded-xl border bg-slate-700/50 border-slate-600 text-white placeholder-slate-400 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition";

  return (
    <div className="min-h-screen bg-slate-900 flex">
      {/* Left branding panel */}
      <div className="hidden lg:flex lg:w-1/2 bg-gradient-to-br from-blue-600 via-blue-700 to-indigo-800 p-12 flex-col justify-between relative overflow-hidden">
        <div className="absolute inset-0 opacity-10">
          <div className="absolute top-20 left-20 w-72 h-72 bg-white rounded-full blur-3xl" />
          <div className="absolute bottom-20 right-20 w-96 h-96 bg-blue-300 rounded-full blur-3xl" />
        </div>
        <div className="relative">
          <div className="flex items-center gap-3 mb-12">
            <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center">
              <Heart className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-white">MemberXP</h1>
              <p className="text-blue-200 text-xs uppercase tracking-widest">Powered by Rackspace</p>
            </div>
          </div>
          <h2 className="text-4xl font-bold text-white leading-tight mb-4">AI-Powered<br />Care Management</h2>
          <p className="text-blue-100 text-lg leading-relaxed max-w-md">
            From fragmented data to actionable care plans in seconds. Our AI agent builds unified member profiles, identifies care gaps, and triggers workflows automatically.
          </p>
        </div>
        <div className="relative space-y-4">
          <div className="flex items-center gap-3 text-blue-100"><Sparkles className="w-5 h-5" /><span>Amazon Bedrock Claude 3 Haiku</span></div>
          <div className="flex items-center gap-3 text-blue-100"><Shield className="w-5 h-5" /><span>HIPAA-ready serverless architecture</span></div>
        </div>
      </div>

      {/* Right form panel */}
      <div className="flex-1 flex items-center justify-center p-8">
        <div className="w-full max-w-md">
          <div className="lg:hidden text-center mb-8">
            <div className="inline-flex items-center gap-2 bg-blue-600 text-white px-4 py-2 rounded-full mb-4">
              <Heart className="w-5 h-5" /><span className="font-semibold">MemberXP</span>
            </div>
          </div>
          <div className="text-center mb-8">
            <h1 className="text-2xl font-bold text-white">
              {mode === 'login' ? 'Welcome back' : mode === 'signup' ? 'Create account' : 'Verify email'}
            </h1>
            <p className="text-slate-400 mt-2">
              {mode === 'login' ? 'Sign in to the care management portal' : mode === 'signup' ? 'Join the care management team' : `We sent a code to ${pendingEmail}`}
            </p>
          </div>

          <div className="bg-slate-800/50 backdrop-blur-sm rounded-2xl border border-slate-700/50 p-8">
            {mode === 'login' && (
              <form onSubmit={handleLogin} className="space-y-5">
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-1">Email</label>
                  <input type="email" value={email} onChange={e => setEmail(e.target.value)} className={inputCls} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-1">Password</label>
                  <input type="password" value={password} onChange={e => setPassword(e.target.value)} className={inputCls} />
                </div>
                {error && <p className="text-red-400 text-sm bg-red-900/30 p-3 rounded-lg">{error}</p>}
                <button type="submit" disabled={loading} className="w-full py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition disabled:opacity-50 flex items-center justify-center gap-2">
                  <Shield className="w-4 h-4" />{loading ? 'Signing in...' : 'Sign In'}
                </button>
                <p className="text-center text-sm text-slate-400">
                  {"Don't have an account? "}
                  <button type="button" onClick={() => { setMode('signup'); setError(''); setEmail(''); setPassword(''); }} className="text-blue-400 font-medium hover:underline">Sign up</button>
                </p>
              </form>
            )}

            {mode === 'signup' && (
              <form onSubmit={handleSignUp} className="space-y-5">
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-1">Full Name</label>
                  <input type="text" value={name} onChange={e => setName(e.target.value)} placeholder="Sarah Johnson" className={inputCls} required />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-1">Email</label>
                  <input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="sarah@example.com" className={inputCls} required />
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-1">Password</label>
                  <input type="password" value={password} onChange={e => setPassword(e.target.value)} placeholder="Min 8 characters" className={inputCls} required />
                  <p className="text-xs text-slate-500 mt-1">Must include uppercase, lowercase, number, and special character</p>
                </div>
                {error && <p className="text-red-400 text-sm bg-red-900/30 p-3 rounded-lg">{error}</p>}
                <button type="submit" disabled={loading} className="w-full py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition disabled:opacity-50 flex items-center justify-center gap-2">
                  <UserPlus className="w-4 h-4" />{loading ? 'Creating account...' : 'Create Account'}
                </button>
                <p className="text-center text-sm text-slate-400">
                  Already have an account?{' '}
                  <button type="button" onClick={() => { setMode('login'); setError(''); setEmail('sarah@example.com'); setPassword('TestPass123!'); }} className="text-blue-400 font-medium hover:underline">Sign in</button>
                </p>
              </form>
            )}

            {mode === 'confirm' && (
              <form onSubmit={handleConfirm} className="space-y-5">
                <div className="text-center mb-2">
                  <div className="w-14 h-14 bg-blue-500/20 rounded-full flex items-center justify-center mx-auto mb-3">
                    <Mail className="w-7 h-7 text-blue-400" />
                  </div>
                  <p className="text-sm text-slate-400">Enter the verification code sent to your email</p>
                </div>
                <div>
                  <input type="text" value={code} onChange={e => setCode(e.target.value)} placeholder="123456" className={inputCls + " text-center text-2xl tracking-widest"} required />
                </div>
                {error && <p className="text-red-400 text-sm bg-red-900/30 p-3 rounded-lg">{error}</p>}
                <button type="submit" disabled={loading} className="w-full py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-xl transition disabled:opacity-50">
                  {loading ? 'Verifying...' : 'Verify & Sign In'}
                </button>
                <button type="button" onClick={() => { setMode('signup'); setError(''); }} className="w-full flex items-center justify-center gap-1 text-sm text-slate-500 hover:text-blue-400">
                  <ArrowLeft className="w-3 h-3" /> Back to sign up
                </button>
              </form>
            )}
            <p className="text-xs text-slate-600 text-center mt-4">Protected by AWS Cognito</p>
          </div>
        </div>
      </div>
    </div>
  );
}
