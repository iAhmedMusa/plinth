export interface UserProfile {
  id: string;
  fullName: string;
  email: string;
  phoneNumber?: string;
  country?: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateUserProfileRequest {
  fullName: string;
  email: string;
  phoneNumber?: string;
  country?: string;
  isActive?: boolean;
}

export interface UpdateUserProfileRequest {
  fullName?: string;
  email?: string;
  phoneNumber?: string;
  country?: string;
  isActive?: boolean;
}