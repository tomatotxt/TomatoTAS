return function()
    local Q = {}
    function Q.normalize(x, y, z, w)
        local n = math.sqrt(x*x + y*y + z*z + w*w)
        assert(n > 1e-12 and n < math.huge, "Invalid quaternion")
        return x/n, y/n, z/n, w/n
    end
    function Q.fromMatrix(a,b,c,d,e,f,g,h,i)
        local x,y,z,w
        local trace = a+e+i
        if trace > 0 then
            local s = math.sqrt(trace+1)*2
            w,x,y,z = s/4,(h-f)/s,(c-g)/s,(d-b)/s
        elseif a > e and a > i then
            local s = math.sqrt(1+a-e-i)*2
            w,x,y,z = (h-f)/s,s/4,(b+d)/s,(c+g)/s
        elseif e > i then
            local s = math.sqrt(1+e-a-i)*2
            w,x,y,z = (c-g)/s,(b+d)/s,s/4,(f+h)/s
        else
            local s = math.sqrt(1+i-a-e)*2
            w,x,y,z = (d-b)/s,(c+g)/s,(f+h)/s,s/4
        end
        return Q.normalize(x,y,z,w)
    end
    function Q.matrix(x,y,z,w)
        x,y,z,w = Q.normalize(x,y,z,w)
        return 1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),
            2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),
            2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)
    end
    function Q.slerp(a,b,t)
        local dot = a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4]
        local sign = if dot < 0 then -1 else 1
        dot = math.clamp(math.abs(dot),0,1)
        local u,v = 1-t,t
        if dot < 0.9995 then
            local angle = math.acos(dot)
            u,v = math.sin((1-t)*angle)/math.sin(angle),math.sin(t*angle)/math.sin(angle)
        end
        return {Q.normalize(a[1]*u+b[1]*v*sign,a[2]*u+b[2]*v*sign,a[3]*u+b[3]*v*sign,a[4]*u+b[4]*v*sign)}
    end
    return Q
end
