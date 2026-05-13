import re

with open('firestore.rules', 'r') as f:
    content = f.read()

# 1. users restriction
old_users = """    // --- 1. 유저 정보 (Top-level) ---
    match /users/{userId} {
      allow read, write: if isSignedIn() && (uid() == userId || isAdmin());
    }"""
new_users = """    // --- 1. 유저 정보 (Top-level) ---
    match /users/{userId} {
      allow read: if isSignedIn() && (uid() == userId || isAdmin());
      allow create: if isSignedIn() && uid() == userId;
      // 보안 강화: 권한 및 멤버십 필드 임의 수정(Privilege Escalation) 원천 차단
      allow update: if isSignedIn() && (
        isAdmin() || 
        (uid() == userId && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['storeId', 'workerId', 'role', 'isDemo']))
      );
      allow delete: if isSignedIn() && (uid() == userId || isAdmin());
    }"""
content = content.replace(old_users, new_users)

# 2. stores read restriction
old_stores = """    // --- 2. 매장 정보 및 하위 컬렉션 ---
    match /stores/{storeId} {
      allow read: if isSignedIn();"""
new_stores = """    // --- 2. 매장 정보 및 하위 컬렉션 ---
    match /stores/{storeId} {
      allow read: if isStoreMember(storeId) || isAdmin();"""
content = content.replace(old_stores, new_stores)

# 3. workers hijacking protection
old_workers = """      // 직원 목록 (workers)
      match /workers/{workerId} {
        allow read: if isSignedIn();
        // 알바생이 본인의 uid를 등록할 수 있게 허용
        allow update: if isStoreMember(storeId) || (isSignedIn() && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['uid']));
        allow create, delete: if isStoreMember(storeId);
      }"""
new_workers = """      // 직원 목록 (workers)
      match /workers/{workerId} {
        allow read: if isStoreMember(storeId) || isAdmin();
        // 알바생이 본인의 uid를 등록할 수 있게 허용 (하이재킹 방지 조건 추가)
        allow update: if isStoreMember(storeId) || (
          isSignedIn() && 
          request.resource.data.diff(resource.data).affectedKeys().hasOnly(['uid']) &&
          request.resource.data.uid == uid() &&
          (resource.data.uid == null || resource.data.uid == '')
        );
        allow create, delete: if isStoreMember(storeId);
      }"""
content = content.replace(old_workers, new_workers)

# 4. substitutions and educationRecords
old_subs_edu = """    match /substitutions/{docId} {
      allow read, write: if isSignedIn();
    }
    match /educationRecords/{docId} {
      allow read, write: if isSignedIn();
    }"""
new_subs_edu = """    match /substitutions/{docId} {
      allow read, update, delete: if isSignedIn() && (isAdmin() || isStoreMember(resource.data.get('storeId', '')));
      allow create: if isSignedIn() && (isAdmin() || isStoreMember(request.resource.data.get('storeId', '')));
    }
    match /educationRecords/{docId} {
      allow read, update, delete: if isSignedIn() && (isAdmin() || isStoreMember(resource.data.get('storeId', '')));
      allow create: if isSignedIn() && (isAdmin() || isStoreMember(request.resource.data.get('storeId', '')));
    }"""
content = content.replace(old_subs_edu, new_subs_edu)

# 5. invites
old_invites = """    // --- 5. 초대 및 통계 ---
    match /invites/{inviteId} {
      allow read: if true;
      allow write: if isSignedIn();
    }"""
new_invites = """    // --- 5. 초대 및 통계 ---
    match /invites/{inviteId} {
      allow read: if true;
      allow create: if isSignedIn() && isStoreMember(request.resource.data.get('storeId', ''));
      allow update, delete: if isSignedIn() && isStoreMember(resource.data.get('storeId', ''));
    }"""
content = content.replace(old_invites, new_invites)

# 6. notificationQueue
old_notif = """    // --- 6. 푸시 알림 큐 ---
    match /notificationQueue/{docId} {
      allow write: if isSignedIn();
    }"""
new_notif = """    // --- 6. 푸시 알림 큐 ---
    match /notificationQueue/{docId} {
      allow create: if isSignedIn() && isStoreMember(request.resource.data.get('storeId', ''));
      allow update, delete: if isSignedIn() && isStoreMember(resource.data.get('storeId', ''));
    }"""
content = content.replace(old_notif, new_notif)

with open('firestore.rules', 'w') as f:
    f.write(content)
