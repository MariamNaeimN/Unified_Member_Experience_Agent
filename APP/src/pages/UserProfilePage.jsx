import { User, Mail, Shield, Clock, Heart, Settings } from 'lucide-react';

export default function UserProfilePage({ user }) {
  const initials = (user.name || 'U').split(' ').map(n => n[0]).join('').toUpperCase();
  const joinDate = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long' });

  return (
    <div className="p-8 max-w-3xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">My Profile</h1>

      {/* Profile Card */}
      <div className="bg-white rounded-2xl border border-gray-200 overflow-hidden mb-6">
        <div className="bg-gradient-to-r from-blue-600 to-indigo-600 px-8 py-10 flex items-center gap-6">
          <div className="w-20 h-20 bg-white/20 backdrop-blur-sm rounded-2xl flex items-center justify-center text-white text-2xl font-bold">
            {initials}
          </div>
          <div className="text-white">
            <h2 className="text-2xl font-bold">{user.name}</h2>
            <p className="text-white/70 mt-1">{user.email}</p>
          </div>
        </div>

        <div className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="flex items-start gap-3 bg-gray-50 rounded-xl p-4">
              <div className="w-10 h-10 bg-blue-100 text-blue-600 rounded-lg flex items-center justify-center shrink-0">
                <User className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-gray-400">Full Name</p>
                <p className="font-semibold text-gray-900">{user.name}</p>
              </div>
            </div>

            <div className="flex items-start gap-3 bg-gray-50 rounded-xl p-4">
              <div className="w-10 h-10 bg-purple-100 text-purple-600 rounded-lg flex items-center justify-center shrink-0">
                <Mail className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-gray-400">Email</p>
                <p className="font-semibold text-gray-900">{user.email}</p>
              </div>
            </div>

            <div className="flex items-start gap-3 bg-gray-50 rounded-xl p-4">
              <div className="w-10 h-10 bg-green-100 text-green-600 rounded-lg flex items-center justify-center shrink-0">
                <Shield className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-gray-400">Role</p>
                <p className="font-semibold text-gray-900">Care Manager</p>
              </div>
            </div>

            <div className="flex items-start gap-3 bg-gray-50 rounded-xl p-4">
              <div className="w-10 h-10 bg-orange-100 text-orange-600 rounded-lg flex items-center justify-center shrink-0">
                <Clock className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-gray-400">Member Since</p>
                <p className="font-semibold text-gray-900">{joinDate}</p>
              </div>
            </div>

            <div className="flex items-start gap-3 bg-gray-50 rounded-xl p-4">
              <div className="w-10 h-10 bg-red-100 text-red-600 rounded-lg flex items-center justify-center shrink-0">
                <Heart className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-gray-400">Department</p>
                <p className="font-semibold text-gray-900">Care Management</p>
              </div>
            </div>

            <div className="flex items-start gap-3 bg-gray-50 rounded-xl p-4">
              <div className="w-10 h-10 bg-gray-200 text-gray-600 rounded-lg flex items-center justify-center shrink-0">
                <Settings className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-gray-400">Status</p>
                <p className="font-semibold text-green-600">Active</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Auth Info */}
      <div className="bg-white rounded-2xl border border-gray-200 p-6">
        <h3 className="font-semibold text-gray-900 mb-4 flex items-center gap-2">
          <Shield className="w-4 h-4 text-blue-600" /> Authentication
        </h3>
        <div className="space-y-3 text-sm">
          <div className="flex justify-between py-2 border-b border-gray-100">
            <span className="text-gray-500">Provider</span>
            <span className="font-medium text-gray-900">AWS Cognito</span>
          </div>
          <div className="flex justify-between py-2 border-b border-gray-100">
            <span className="text-gray-500">Auth Method</span>
            <span className="font-medium text-gray-900">Email + Password</span>
          </div>
          <div className="flex justify-between py-2">
            <span className="text-gray-500">Session</span>
            <span className="font-medium text-green-600">Authenticated</span>
          </div>
        </div>
      </div>
    </div>
  );
}
