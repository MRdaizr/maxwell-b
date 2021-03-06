// Mark the threads that need to load from global memory.
const bool adj_dims =  (((_X >= -1) && (_X <= {{ dims[0] }})) && \
                        ((_Y >= -1) && (_Y <= {{ dims[1] }})) && \
                        ((_Z >= -1) && (_Z <= {{ dims[2] }})));

// Set relevant field pointers to create wrap-around periodic grid.
{{ type }} bloch_phaseYZ_x = 1.0;
{{ type }} bloch_phaseYZ_y = 1.0;
{{ type }} bloch_phaseYZ_z = 1.0;

// Set relevant field pointers to create wrap-around periodic grid.
if (_Y == -1) {
    _Y = {{ dims[1]-1 }};
	bloch_phaseYZ_x *= conj(bloch_y(0));
	bloch_phaseYZ_y *= conj(bloch_y(1));
	bloch_phaseYZ_z *= conj(bloch_y(2));
}
if (_Y == {{ dims[1] }}) {
    _Y = 0;
	bloch_phaseYZ_x *= bloch_y(0);
	bloch_phaseYZ_y *= bloch_y(1);
	bloch_phaseYZ_z *= bloch_y(2);
}
if (_Z == -1) {
    _Z = {{ dims[2]-1 }};
	bloch_phaseYZ_x *= conj(bloch_z(0));
	bloch_phaseYZ_y *= conj(bloch_z(1));
	bloch_phaseYZ_z *= conj(bloch_z(2));
}
if (_Z == {{ dims[2] }}) {
    _Z = 0;
	bloch_phaseYZ_x *= bloch_z(0);
	bloch_phaseYZ_y *= bloch_z(1);
	bloch_phaseYZ_z *= bloch_z(2);
}

// Some definitions for shared memory.
// Used to get unpadded thread indices.
#define s_ty (_ty + 1)
#define s_tz (_tz + 1)
#define s_tyy (_tyy + 2)
#define s_tzz (_tzz + 2)

// Helper definitions.
#define s_next_field (s_tyy * s_tzz)
#define s_to_local (s_ty * s_tzz + (s_tz))   
#define s_zp +1
#define s_zn -1
#define s_yp +s_tzz
#define s_yn -s_tzz

{{ type }} *Ex_0 = (0 * s_next_field) + (({{ type }}*) _gce_smem) + s_to_local;
{{ type }} *Ey_0 = (1 * s_next_field) + (({{ type }}*) _gce_smem) + s_to_local;
{{ type }} *Ez_0 = (2 * s_next_field) + (({{ type }}*) _gce_smem) + s_to_local;
{{ type }} *Hx_0 = (3 * s_next_field) + (({{ type }}*) _gce_smem) + s_to_local;
{{ type }} *Hy_0 = (4 * s_next_field) + (({{ type }}*) _gce_smem) + s_to_local;
{{ type }} *Hz_0 = (5 * s_next_field) + (({{ type }}*) _gce_smem) + s_to_local;

// Local memory.
{{ type }} Ey_p, Ez_p, Hy_n, Hz_n;
{{ type }} vx, vy, vz;
{{ type }} px, py, pz, py_p, pz_p;

int xn, xp;
{{ type }} bloch_phaseX_x = 1;
{{ type }} bloch_phaseX_y = 1;
{{ type }} bloch_phaseX_z = 1;
if (_X == 0) {
    bloch_phaseX_x = conj(bloch_x(0));
    bloch_phaseX_y = conj(bloch_x(1));
    bloch_phaseX_z = conj(bloch_x(2));
    xn = {{ dims[0]-1 }}; // Wrap-around step in the negative direction.
} else {
    xn = -1;
}

// Load E-fields into shared memory.
if (adj_dims) {
    // Load in p = r + beta * p.
    Ex_0[0] = bloch_phaseX_x * bloch_phaseYZ_x * (Xx(-1,0,0)) * 
                (sqrt_sx1(_X+xn) * sqrt_sy0(_Y) * sqrt_sz0(_Z));
    Ey_0[0] = bloch_phaseX_y * bloch_phaseYZ_y * (Xy(-1,0,0)) * 
                (sqrt_sx0(_X+xn) * sqrt_sy1(_Y) * sqrt_sz0(_Z));
    Ez_0[0] = bloch_phaseX_z * bloch_phaseYZ_z * (Xz(-1,0,0)) * 
                (sqrt_sx0(_X+xn) * sqrt_sy0(_Y) * sqrt_sz1(_Z));

    // Ey_p = Ry(0,0,0) + beta * Ey(0,0,0);
    py_p = Xy(0,0,0);
    Ey_p = bloch_phaseYZ_y * (py_p) * (sqrt_sx0(_X) * sqrt_sy1(_Y) * sqrt_sz0(_Z));

    // Ez_p = Rz(0,0,0) + beta * Ez(0,0,0);
    pz_p = Xz(0,0,0);
    Ez_p = bloch_phaseYZ_z * (pz_p) * (sqrt_sx0(_X) * sqrt_sy0(_Y) * sqrt_sz1(_Z));
}
__syncthreads();

// Calculate H-fields and store in shared_memory.
// Hy.
if ((_ty != -1) && (_ty != _tyy) && (_tz != _tzz)) {
    Hy_0[0] = my(-1,0,0) * (sx1(_X+xn) * (Ez_0[0] - Ez_p) - 
                sz1(_Z) * (Ex_0[0] - Ex_0[s_zp]));
}

// Hz.
if ((_ty != _tyy) && (_tz != -1) && (_tz != _tzz)) {
    Hz_0[0] = mz(-1,0,0) * (sy1(_Y) * (Ex_0[0] - Ex_0[s_yp]) - 
                sx1(_X+xn) * (Ey_0[0] - Ey_p));
}
__syncthreads();

for (; _X < _x_end ; _X += _txx) {
    // We've moved ahead in X, so transfer appropriate field values.
    Ey_0[0] = Ey_p;
    Ez_0[0] = Ez_p;
    Hy_n = Hy_0[0];
    Hz_n = Hz_0[0];

    py = py_p;
    pz = pz_p;

    // Load E-fields into shared memory.
    if (_X == {{ dims[0]-1 }}) {
        bloch_phaseX_x = bloch_x(0);
        bloch_phaseX_y = bloch_x(1);
        bloch_phaseX_z = bloch_x(2);
        xp = {{ -(dims[0]-1) }};
    } else {
        xp = +1;
    	bloch_phaseX_x = 1;
    	bloch_phaseX_y = 1;
    	bloch_phaseX_z = 1;
    }
    if (adj_dims) {
        px = Xx(0,0,0);
        Ex_0[0] = bloch_phaseYZ_x * (px) * (sqrt_sx1(_X) * sqrt_sy0(_Y) * sqrt_sz0(_Z));

        py_p = Xy(+1,0,0);    
        Ey_p = bloch_phaseX_y * bloch_phaseYZ_y * (py_p) * (sqrt_sx0(_X+xp) * sqrt_sy1(_Y) * sqrt_sz0(_Z));

        pz_p = Xz(+1,0,0);
        Ez_p = bloch_phaseX_z * bloch_phaseYZ_z * (pz_p) * (sqrt_sx0(_X+xp) * sqrt_sy0(_Y) * sqrt_sz1(_Z));
    }

    __syncthreads();

    // Calculate H-fields and store in shared_memory.
    {% if mu_equals_1 == True %}
    // Hx.
    if ((_ty != _tyy) && (_tz != _tzz)) {
        Hx_0[0] =   (sz1(_Z) * (Ey_0[0] - Ey_0[s_zp]) - 
                    sy1(_Y) * (Ez_0[0] - Ez_0[s_yp]));
    }

    // Hy.
    if ((_ty != -1) && (_ty != _tyy) && (_tz != _tzz)) {
        Hy_0[0] =   (sx1(_X) * (Ez_0[0] - Ez_p) - 
                    sz1(_Z) * (Ex_0[0] - Ex_0[s_zp]));
    }

    // Hz.
    if ((_ty != _tyy) && (_tz != -1) && (_tz != _tzz)) {
        Hz_0[0] =   (sy1(_Y) * (Ex_0[0] - Ex_0[s_yp]) - 
                    sx1(_X) * (Ey_0[0] - Ey_p));
    }
    {% else %}
    // Hx.
    if ((_ty != _tyy) && (_tz != _tzz)) {
        Hx_0[0] =   mx(0,0,0) * (sz1(_Z) * (Ey_0[0] - Ey_0[s_zp]) - 
                    sy1(_Y) * (Ez_0[0] - Ez_0[s_yp]));
    }

    // Hy.
    if ((_ty != -1) && (_ty != _tyy) && (_tz != _tzz)) {
        Hy_0[0] =   my(0,0,0) * (sx1(_X) * (Ez_0[0] - Ez_p) - 
                    sz1(_Z) * (Ex_0[0] - Ex_0[s_zp]));
    }

    // Hz.
    if ((_ty != _tyy) && (_tz != -1) && (_tz != _tzz)) {
        Hz_0[0] =   mz(0,0,0) * (sy1(_Y) * (Ex_0[0] - Ex_0[s_yp]) - 
                    sx1(_X) * (Ey_0[0] - Ey_p));
    }
    {% endif %}
    __syncthreads();

    // Write out the results.
    if (_in_global && _in_local) {
        {% if full_operator %}

        vx = ((1.0 / (sqrt_sx1(_X) * sqrt_sy0(_Y) * sqrt_sz0(_Z))) *
                    (sy0(_Y) * (Hz_0[0] - Hz_0[s_yn])
                    - sz0(_Z) * (Hy_0[0] - Hy_0[s_zn])
                    - ex(0,0,0) * Ex_0[0]));
        vy = ((1.0 / (sqrt_sx0(_X) * sqrt_sy1(_Y) * sqrt_sz0(_Z))) *
                    (sz0(_Z) * (Hx_0[0] - Hx_0[s_zn]) 
                    - sx0(_X) * (Hz_0[0] - Hz_n) 
                    - ey(0,0,0) * Ey_0[0]));
        vz = ((1.0 / (sqrt_sx0(_X) * sqrt_sy0(_Y) * sqrt_sz1(_Z))) *
                    (sx0(_X) * (Hy_0[0] - Hy_n) 
                    - sy0(_Y) * (Hx_0[0] - Hx_0[s_yn]) 
                    - ez(0,0,0) * Ez_0[0]));

        Bx(0,0,0) = vx;
        By(0,0,0) = vy;
        Bz(0,0,0) = vz;

        {% else %}
        Bx(0,0,0) = Hx_0[0];
        By(0,0,0) = Hy_0[0];
        Bz(0,0,0) = Hz_0[0];

        {% endif %}
    }
    __syncthreads();
}
